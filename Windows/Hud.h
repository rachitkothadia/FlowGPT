#pragma once
#include "Platform.h"
namespace flow {
inline HICON waveformIcon() {
    BITMAPV5HEADER header{};header.bV5Size=sizeof(header);header.bV5Width=32;header.bV5Height=-32;header.bV5Planes=1;header.bV5BitCount=32;header.bV5Compression=BI_BITFIELDS;header.bV5RedMask=0x00FF0000;header.bV5GreenMask=0x0000FF00;header.bV5BlueMask=0x000000FF;header.bV5AlphaMask=0xFF000000;
    void* pixels{};HDC dc=GetDC(nullptr);HBITMAP color=CreateDIBSection(dc,reinterpret_cast<BITMAPINFO*>(&header),DIB_RGB_COLORS,&pixels,nullptr,0);ReleaseDC(nullptr,dc);
    if(!color)return LoadIconW(nullptr,IDI_APPLICATION);
    auto data=static_cast<uint32_t*>(pixels);std::fill(data,data+32*32,0u);
    int heights[]{10,18,26,18,10};for(int bar=0;bar<5;++bar)for(int x=4+bar*5;x<7+bar*5;++x)for(int y=(32-heights[bar])/2;y<(32+heights[bar])/2;++y)data[y*32+x]=0xFF548B78;
    HBITMAP mask=CreateBitmap(32,32,1,1,nullptr);ICONINFO info{TRUE,0,0,mask,color};HICON icon=CreateIconIndirect(&info);DeleteObject(color);DeleteObject(mask);return icon;
}
class Hud {
    HWND window_{};
    bool processing_=false;
    double level_=0;
    unsigned frame_=0;
    static LRESULT CALLBACK procedure(HWND h,UINT m,WPARAM w,LPARAM l) {
        auto self=reinterpret_cast<Hud*>(GetWindowLongPtrW(h,GWLP_USERDATA));
        if(m==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
        if(self&&m==WM_LBUTTONUP){if(self->finish)self->finish();return 0;}
        if(self&&m==WM_PAINT){self->paint();return 0;}
        return DefWindowProcW(h,m,w,l);
    }
    void paint(){PAINTSTRUCT ps{};HDC dc=BeginPaint(window_,&ps);RECT r{};GetClientRect(window_,&r);HBRUSH brush=CreateSolidBrush(RGB(20,24,23));FillRect(dc,&r,brush);DeleteObject(brush);
        int height=r.bottom,width=r.right;double scale=height/36.0;auto pen=CreatePen(PS_SOLID,int(2*scale),RGB(230,242,236));auto previous=SelectObject(dc,pen);auto hollow=SelectObject(dc,GetStockObject(NULL_BRUSH));int x=int(22*scale),y=height/2;
        if(processing_){int rad=int(7*scale);double t=frame_*0.22;Arc(dc,x-rad,y-rad,x+rad,y+rad,x+int(rad*cos(t)),y+int(rad*sin(t)),x+int(rad*cos(t+4)),y+int(rad*sin(t+4)));}
        else{RoundRect(dc,x-int(4*scale),y-int(8*scale),x+int(4*scale),y+int(3*scale),int(5*scale),int(5*scale));Arc(dc,x-int(7*scale),y-int(2*scale),x+int(7*scale),y+int(7*scale),x-int(7*scale),y,x+int(7*scale),y);MoveToEx(dc,x,y+int(7*scale),nullptr);LineTo(dc,x,y+int(11*scale));}
        for(int i=0;i<7;++i){int bar=int((4+level_*(8+6*cos(i*0.9)))*scale);int bx=int(48*scale+i*6*scale);if(bx>=width-10)break;MoveToEx(dc,bx,y-bar/2,nullptr);LineTo(dc,bx,y+bar/2);}
        SelectObject(dc,hollow);SelectObject(dc,previous);DeleteObject(pen);EndPaint(window_,&ps);
    }
public:
    std::function<void()> finish;
    Hud(){WNDCLASSW c{};c.lpfnWndProc=procedure;c.hInstance=GetModuleHandleW(nullptr);c.lpszClassName=L"FlowGPTHud";c.hCursor=LoadCursorW(nullptr,IDC_ARROW);RegisterClassW(&c);window_=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE|WS_EX_TOPMOST,c.lpszClassName,L"FlowGPT recording",WS_POPUP,0,0,116,36,nullptr,nullptr,c.hInstance,nullptr);SetWindowLongPtrW(window_,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(this));}
    ~Hud(){DestroyWindow(window_);}
    void update(State state,double level){if(!busy(state)){ShowWindow(window_,SW_HIDE);return;}POINT mouse{};GetCursorPos(&mouse);HMONITOR monitor=MonitorFromPoint(mouse,MONITOR_DEFAULTTONEAREST);MONITORINFO info{sizeof(info)};GetMonitorInfoW(monitor,&info);UINT dpi=GetDpiForWindow(window_);int width=MulDiv(116,dpi,96),height=MulDiv(36,dpi,96);SetWindowPos(window_,HWND_TOPMOST,(info.rcWork.left+info.rcWork.right-width)/2,info.rcWork.bottom-height-6,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);SetWindowRgn(window_,CreateRoundRectRgn(0,0,width+1,height+1,height,height),TRUE);processing_=state!=State::recording;level_=level;++frame_;InvalidateRect(window_,nullptr,FALSE);}
    HWND handle()const{return window_;}
};
}
