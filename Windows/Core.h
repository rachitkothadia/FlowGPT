#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <vector>

namespace flow {
enum class State { idle, starting, recording, transcribing, inserting, finished, attempted, error, cancelled };
inline bool busy(State s) { return s == State::starting || s == State::recording || s == State::transcribing || s == State::inserting; }
// A background composer can keep its Dictate button visible behind the recorder.
inline bool recorderEnded(bool ready,bool recording,bool transcribing){return !recording&&(ready||transcribing);}
inline bool canInsertTranscript(bool local,bool targetPending,bool targetUsable){return !local&&!targetPending&&targetUsable;}
struct Session {
    State state = State::idle;
    uint64_t generation = 0;
    bool stopRequested = false, local = false;
    bool begin(bool preview) {
        if (busy(state)) return false;
        ++generation; stopRequested = false; local = preview; state = State::starting; return true;
    }
    bool current(uint64_t token) const { return token == generation && busy(state); }
    bool stop() {
        if (state == State::starting) { stopRequested = true; return false; }
        if (state != State::recording) return false;
        state = State::transcribing; return true;
    }
    void cancel() { ++generation; stopRequested = false; state = State::cancelled; }
};
struct Recovery {
    unsigned attempts = 0;
    double after = 0;
    bool request(double now, bool active, bool login, bool draft) {
        if (active || login || draft || now < after) return false;
        attempts = std::min(attempts + 1, 5u);
        after = now + std::min(30.0, std::pow(2.0, attempts)); return true;
    }
    void ready() { attempts = 0; after = 0; }
};
inline bool sameTarget(uintptr_t originalWindow, uintptr_t currentWindow, const std::vector<int>& originalId, const std::vector<int>& currentId) {
    return originalWindow != 0 && originalWindow == currentWindow && !originalId.empty() && originalId == currentId;
}
inline bool mayRestore(uint32_t owned, uint32_t current) { return owned == current; }
// Stop the producer on its capture thread, accept its final pending packets,
// and only then close the queue. Never freeze from the requesting UI thread.
template<typename Queue,typename Stop,typename Drain>
void stopAndDrainCapture(Queue& queue,Stop stop,Drain drain){
    struct Freeze{Queue& queue;~Freeze(){queue.freeze();}}freeze{queue};stop();drain();
}
inline bool validText(const std::wstring& s) { return !s.empty() && s.size() <= 100000 && s.find(L'\0') == std::wstring::npos; }
struct AudioChunk { uint64_t id = 0; std::vector<float> samples; };
class AudioQueue {
    mutable std::mutex mutex_;
    std::deque<AudioChunk> chunks_;
    size_t size_ = 0, capacity_;
    uint64_t next_ = 1;
    bool accepting_ = true, failed_ = false;
    double level_ = 0;
public:
    explicit AudioQueue(size_t capacity = 16000 * 30) : capacity_(capacity) {}
    void reset() { std::lock_guard<std::mutex> l(mutex_); chunks_.clear(); size_ = 0; accepting_ = true; failed_ = false; level_ = 0; }
    bool push(const float* data, size_t n) {
        std::lock_guard<std::mutex> l(mutex_);
        if (!accepting_) return false;
        if (n > capacity_ - size_) { failed_ = true; accepting_ = false; return false; }
        double sum = 0;
        for (size_t i = 0; i < n; ++i) sum += double(data[i]) * data[i];
        level_ = n ? std::min(1.0, std::sqrt(sum / double(n)) * 6) : 0;
        if (n) { chunks_.push_back({next_++, std::vector<float>(data, data + n)}); size_ += n; }
        return true;
    }
    AudioChunk peek() const { std::lock_guard<std::mutex> l(mutex_); return chunks_.empty() ? AudioChunk{} : chunks_.front(); }
    AudioChunk peekBatch(size_t maximum) const {
        std::lock_guard<std::mutex> l(mutex_);AudioChunk batch;
        for(const auto& chunk:chunks_){if(!batch.samples.empty()&&batch.samples.size()+chunk.samples.size()>maximum)break;batch.id=chunk.id;batch.samples.insert(batch.samples.end(),chunk.samples.begin(),chunk.samples.end());if(batch.samples.size()>=maximum)break;}
        return batch;
    }
    bool acknowledgeThrough(uint64_t id) {
        std::lock_guard<std::mutex> l(mutex_);auto last=std::find_if(chunks_.begin(),chunks_.end(),[id](const auto& c){return c.id==id;});if(last==chunks_.end())return false;
        do{const auto front=chunks_.front().id;size_-=chunks_.front().samples.size();chunks_.pop_front();if(front==id)break;}while(!chunks_.empty());return true;
    }
    bool acknowledge(uint64_t id) { std::lock_guard<std::mutex> l(mutex_); if (chunks_.empty() || chunks_.front().id != id) return false; size_ -= chunks_.front().samples.size(); chunks_.pop_front(); return true; }
    size_t pending() const { std::lock_guard<std::mutex> l(mutex_); return size_; }
    bool failed() const { std::lock_guard<std::mutex> l(mutex_); return failed_; }
    double level() const { std::lock_guard<std::mutex> l(mutex_); return level_; }
    void freeze() { std::lock_guard<std::mutex> l(mutex_); accepting_ = false; level_ = 0; }
};
inline std::string base64(const void* data, size_t n) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    auto bytes = static_cast<const unsigned char*>(data);
    std::string result; result.reserve(((n + 2) / 3) * 4);
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = uint32_t(bytes[i]) << 16;
        if (i + 1 < n) v |= uint32_t(bytes[i + 1]) << 8;
        if (i + 2 < n) v |= bytes[i + 2];
        result += alphabet[(v >> 18) & 63]; result += alphabet[(v >> 12) & 63];
        result += i + 1 < n ? alphabet[(v >> 6) & 63] : '=';
        result += i + 2 < n ? alphabet[v & 63] : '=';
    }
    return result;
}
}
