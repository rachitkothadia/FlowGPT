#include "../Core.h"
#include "../Formatting.h"
#include "../ReleasePolicy.h"
#include <iostream>
#include "../../Shared/Tests/Fixtures.h"
#include <stdexcept>
#include <thread>

static unsigned count = 0;
void check(bool value, const char* name) { if (!value) throw std::runtime_error(name); ++count; }
int main() {
    using namespace flow;
    Session s;
    check(s.begin(false), "begin"); auto token = s.generation;
    check(!s.begin(true), "rapid start rejected");
    check(!s.stop() && s.stopRequested, "stop during startup remembered");
    s.state = State::recording;
    check(s.stop() && s.state == State::transcribing, "finish transition");
    check(!s.stop(), "duplicate finish rejected"); s.cancel();
    check(!s.current(token), "cancel invalidates late completion");
    check(s.begin(true) && s.local && !s.stopRequested, "new local preview");
    Recovery r;
    check(!r.request(0, true, false, false), "active protected");
    check(!r.request(0, false, true, false), "login protected");
    check(!r.request(0, false, false, true), "draft protected");
    check(r.request(0, false, false, false) && r.after == 2, "first backoff");
    check(!r.request(1, false, false, false), "retry rate bounded");
    for (int i = 0; i < 10; ++i) check(r.request(r.after, false, false, false), "retry accepted");
    check(r.attempts == 5 && r.after < 400, "capped backoff"); r.ready();
    check(r.attempts == 0 && r.after == 0, "recovery reset");
    check(sameTarget(1, 1, {1,2}, {1,2}), "same field");
    check(!sameTarget(1, 2, {1}, {1}), "different window");
    check(!sameTarget(1, 1, {1}, {2}), "different field");
    check(!sameTarget(1, 1, {}, {}), "missing identity rejected");
    check(mayRestore(7,7) && !mayRestore(7,8), "new user clipboard copy retained");
    check(validText(L"हिन्दी English मराठी 🎤\n1. C++"), "mixed Unicode");
    check(!validText(L"") && !validText(std::wstring(100001,L'x')), "invalid transcript");
    check(!validText(std::wstring(L"a\0b",3)), "embedded NUL");
    check(base64("",0) == "" && base64("a",1) == "YQ==" && base64("ab",2) == "YWI=" && base64("abc",3) == "YWJj", "base64 exact bytes");
    AudioQueue q(5); float a[]{1,2,3}, b[]{4,5}, c[]{6};
    check(q.push(a,3) && q.push(b,2), "queue capacity");
    auto first = q.peek(); check(first.samples == std::vector<float>({1,2,3}), "opening prefix retained");
    check(!q.acknowledge(first.id+1) && q.pending()==5, "wrong acknowledgement refused");
    check(q.acknowledge(first.id) && q.pending()==2, "acknowledge accepted");
    check(q.push(c,1), "space after acknowledgement"); q.freeze();
    check(!q.push(c,1), "stop excludes later audio");
    check(q.peek().samples == std::vector<float>({4,5}), "FIFO order");
    q.reset(); check(q.push(a,3) && !q.push(a,3) && q.failed() && q.pending()==3, "overflow preserves prefix and reports failure");
    q.reset();
    std::thread producer([&]{ for(int i=0;i<10000;++i) { while(!q.push(c,1)) { if(q.failed()) return; } } });
    producer.join(); check(q.pending()<=5 && q.failed(), "concurrent producer bounded");
    AudioQueue batches(20);batches.push(a,3);batches.push(b,2);batches.push(c,1);
    check(batches.peekBatch(4).samples==std::vector<float>({1,2,3}),"batch limit preserves whole packets");auto batch=batches.peekBatch(5);
    check(batch.samples==std::vector<float>({1,2,3,4,5}),"batch retains exact ordered samples");
    check(!batches.acknowledgeThrough(batch.id+99)&&batches.pending()==6,"unknown batch acknowledgement cannot erase audio");
    check(batches.acknowledgeThrough(batch.id)&&batches.pending()==1&&batches.peek().samples==std::vector<float>({6}),"batch acknowledgement removes only accepted prefix");
    AudioQueue stream;std::vector<float> packet(160,0.25f);bool keepsUp=true;
    // Six minutes of 10 ms capture packets, forwarded on a 100 ms UI schedule.
    // This exposes forwarding just one packet per timer tick without wall-clock sleep.
    for(int tick=0;tick<3600;++tick){for(int i=0;i<10;++i)keepsUp=stream.push(packet.data(),packet.size())&&keepsUp;auto delivery=stream.peekBatch(3200);keepsUp=delivery.samples.size()==1600&&stream.acknowledgeThrough(delivery.id)&&stream.pending()==0&&keepsUp;}
    check(keepsUp&&!stream.failed(),"scheduled batches sustain the full capture rate");
    AudioQueue stopRace(8);float prefix[]{1,2},tail[]{3,4};stopRace.push(prefix,2);bool producerStopped=false;
    stopAndDrainCapture(stopRace,[&]{producerStopped=true;check(stopRace.push(tail,1),"in-flight packet remains accepted while hardware stops");},[&]{check(producerStopped,"device stops before pending packets are drained");check(stopRace.push(tail+1,1),"pending final capture packet retained");});
    check(stopRace.peekBatch(8).samples==std::vector<float>({1,2,3,4})&&!stopRace.push(tail,1),"stop preserves exact audio tail then rejects later speech");
    std::vector<std::wstring> preserved={L"hello testing testing",L"मैं कल कल जाऊंगा नहीं शुक्रवार को",L"मराठी English हिन्दी गुजराती ગુજરાતી",L"garam masala Dmart my maby",L"int err = 3; C++ Rust Java Python",L"https://example.com/a/1. /Users/test/file.txt",L"He said \"1. stay 2. leave\"",L"2. second 3. third"};
    check(readableTranscript(L"1.25 litres and 2.50 kilograms")==L"• 1.25 litres\n• and 2.50 kilograms","amounts remain exact in a homogeneous list");
    for(auto& text:preserved)check(readableTranscript(text)==text,"native formatting preserves lexical content");
    check(readableTranscript(L"Tasks: 1. Apples apples 2. दूध milk 3. मराठी") == L"Tasks:\n1. Apples apples\n2. दूध milk\n3. मराठी","explicit sequential items get whitespace only");
    check(readableTranscript(L"1. Apples\n2. pears") == L"1. Apples\n2. pears","existing formatting remains stable");
    std::wstring longList,expectedList;for(unsigned i=1;i<=500;++i){if(i>1){longList+=L" ";expectedList+=L"\n";}auto item=std::to_wstring(i)+L". Item";longList+=item;expectedList+=item;}
    check(readableTranscript(longList)==expectedList,"no small list item limit");
    check(readableTranscript(readableTranscript(longList))==expectedList,"formatting is idempotent");
    check(readableTranscript(L"January 1. That was a date 2. Not a list")==L"January 1. That was a date 2. Not a list","ordinary prose is not treated as a list");
    TranscriptFinalizer finalizer;
    check(!finalizer.accept(L"hello",true,false,false,10),"final text waits for stability");
    check(!finalizer.accept(L"hello",false,false,true,10.25),"provider work resets stability");
    check(!finalizer.accept(L"hello",true,false,false,10.3),"same text after pending state restarts stability");
    check(finalizer.accept(L"hello",true,false,false,10.51),"stable final text completes");
    check(!finalizer.accept(L"hello tail",true,false,false,10.52),"late tail is not truncated");
    check(updateVersion(L"1.10.0")>updateVersion(L"1.9.0"),"versions compared numerically");
    check(!updateVersion(L"1.2")&&!updateVersion(L"1.2.3.4")&&!updateVersion(L"1.2.x")&&!updateVersion(L"1.9999999.0"),"malformed update versions refused");
    check(trustedUpdateAsset(L"https://github.com/rachitkothadia/FlowGPT/releases/download/v1/file.exe")&&!trustedUpdateAsset(L"https://github.com/other/FlowGPT/releases/download/v1/file.exe")&&!trustedUpdateAsset(L"http://github.com/rachitkothadia/FlowGPT/releases/download/v1/file.exe"),"updates confined to own HTTPS release assets");
    const std::wstring digest(64,L'a');
    check(releaseChecksum(digest+L"  app.exe\n",L"app.exe")==digest,"checksum exact release file accepted");
    check(!releaseChecksum(digest+L"  app.exe\n"+digest+L"  app.exe\n",L"app.exe"),"duplicate checksum refused");
    check(!releaseChecksum(std::wstring(64,L'g')+L"  app.exe\n",L"app.exe"),"nonhex checksum refused");
    check(!releaseChecksum(digest+L"  other.exe\n",L"app.exe"),"missing filename checksum refused");
    for(const auto& fixture:formattingFixtures()) {
        auto source=transcriptWide(fixture.input), expected=transcriptWide(fixture.expected);
        auto output=readableTranscript(source);
        check(output==expected,fixture.name);
        check(readableTranscript(output)==output,"shared fixtures are idempotent");
    }
    check(readableTranscript(L"😀 Marathi मराठी हिन्दी हिंदी") == L"😀 Marathi मराठी हिन्दी हिंदी","supplementary Unicode exact round trip");
    for(const auto& currency:flow_format::currencyCodes()) {
        auto raw=currency.first+" 123.45";
        auto expected=flow_format::moneyDisplay(currency.second,"123.45");
        check(flow_format::normalizeMoney(raw)==expected,"every CLDR currency code formats without amount drift");
    }
    std::cout << count << " portable core checks passed\n";
}
