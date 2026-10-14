#pragma once
#include "Platform.h"
#include <gdiplus.h>
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
    ULONG_PTR graphicsToken_{};
    bool active_=false,processing_=false;
    double targetLevel_=0,level_=0;
    HMONITOR monitor_{};
    static LRESULT CALLBACK procedure(HWND h,UINT m,WPARAM w,LPARAM l){
        auto self=reinterpret_cast<Hud*>(GetWindowLongPtrW(h,GWLP_USERDATA));
        if(m==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
        if(self){
            try{
                if(m==WM_LBUTTONUP){if(self->finish)self->finish();return 0;}
                if(m==WM_TIMER){self->level_+=(self->targetLevel_-self->level_)*0.22;self->draw();return 0;}
                if(m==WM_DISPLAYCHANGE||m==WM_DPICHANGED){self->position();self->draw();return 0;}
                if(m==WM_PAINT){PAINTSTRUCT p;BeginPaint(h,&p);EndPaint(h,&p);return 0;}
            }catch(...){ShowWindow(h,SW_HIDE);self->active_=false;KillTimer(h,1);}
        }return DefWindowProcW(h,m,w,l);
    }
    void position(){
        if(!active_)return;
        if(!monitor_)monitor_=MonitorFromWindow(GetForegroundWindow(),MONITOR_DEFAULTTONEAREST);
        MONITORINFO info{sizeof(info)};
        if(!GetMonitorInfoW(monitor_,&info)){monitor_=MonitorFromWindow(window_,MONITOR_DEFAULTTONEAREST);if(!GetMonitorInfoW(monitor_,&info))return;}
        UINT dpi=GetDpiForWindow(window_);int width=MulDiv(112,dpi,96),height=MulDiv(32,dpi,96);
        SetWindowPos(window_,HWND_TOPMOST,(info.rcWork.left+info.rcWork.right-width)/2,info.rcWork.bottom-height-MulDiv(8,dpi,96),width,height,SWP_NOACTIVATE);
    }
    void draw(){
        if(!active_||!graphicsToken_)return;
        RECT rect{};GetWindowRect(window_,&rect);int width=rect.right-rect.left,height=rect.bottom-rect.top;
        if(width<=0||height<=0)return;
        HDC screen=GetDC(nullptr),memory=CreateCompatibleDC(screen);void* pixels{};
        BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=width;info.bmiHeader.biHeight=-height;
        info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
        HBITMAP bitmap=CreateDIBSection(screen,&info,DIB_RGB_COLORS,&pixels,nullptr,0);
        if(!bitmap){DeleteDC(memory);ReleaseDC(nullptr,screen);return;}
        auto original=SelectObject(memory,bitmap);memset(pixels,0,size_t(width)*height*4);
        {
            Gdiplus::Bitmap surface(width,height,width*4,PixelFormat32bppPARGB,static_cast<BYTE*>(pixels));
            Gdiplus::Graphics g(&surface);g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
            float scale=float(height)/32.0f,diameter=float(height)-2.0f;
            Gdiplus::GraphicsPath shape;shape.AddArc(1.0f,1.0f,diameter,diameter,90.0f,180.0f);shape.AddArc(float(width)-diameter-1.0f,1.0f,diameter,diameter,270.0f,180.0f);shape.CloseFigure();
            Gdiplus::LinearGradientBrush background(Gdiplus::PointF(0,0),Gdiplus::PointF(0,float(height)),Gdiplus::Color(245,32,38,35),Gdiplus::Color(245,16,20,18));
            g.FillPath(&background,&shape);Gdiplus::Pen edge(Gdiplus::Color(55,210,231,221),1.0f);g.DrawPath(&edge,&shape);
            Gdiplus::Pen ink(Gdiplus::Color(235,230,241,235),1.8f*scale);ink.SetStartCap(Gdiplus::LineCapRound);ink.SetEndCap(Gdiplus::LineCapRound);
            float x=21*scale,y=float(height)/2;
            if(processing_)g.DrawArc(&ink,x-6*scale,y-6*scale,12*scale,12*scale,float(fmod(now()*310,360)),270.0f);
            else{
                Gdiplus::GraphicsPath mic;mic.AddArc(x-3.3f*scale,y-7*scale,6.6f*scale,6.6f*scale,180,180);mic.AddArc(x-3.3f*scale,y-2*scale,6.6f*scale,6.6f*scale,0,180);mic.CloseFigure();g.DrawPath(&ink,&mic);
                g.DrawArc(&ink,x-6*scale,y-5*scale,12*scale,12*scale,0,180);g.DrawLine(&ink,x,y+7*scale,x,y+10*scale);
            }
            for(int i=0;i<7;++i){float length=float(3+level_*(6+8*cos(i*0.85)))*scale;length=std::max(3.0f*scale,length);float bx=(46+i*6.5f)*scale;g.DrawLine(&ink,bx,y-length/2,bx,y+length/2);}
            g.Flush(Gdiplus::FlushIntentionSync);
        }
        POINT destination{rect.left,rect.top},source{0,0};SIZE size{width,height};BLENDFUNCTION blend{AC_SRC_OVER,0,255,AC_SRC_ALPHA};
        UpdateLayeredWindow(window_,screen,&destination,&size,memory,&source,0,&blend,ULW_ALPHA);
        SelectObject(memory,original);DeleteObject(bitmap);DeleteDC(memory);ReleaseDC(nullptr,screen);
    }
public:
    std::function<void()> finish;
    Hud(){
        Gdiplus::GdiplusStartupInput input;Gdiplus::GdiplusStartup(&graphicsToken_,&input,nullptr);
        WNDCLASSW c{};c.lpfnWndProc=procedure;c.hInstance=GetModuleHandleW(nullptr);c.lpszClassName=L"FlowGPTHud";c.hCursor=LoadCursorW(nullptr,IDC_ARROW);RegisterClassW(&c);
        window_=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_LAYERED|WS_EX_NOACTIVATE|WS_EX_TOPMOST,c.lpszClassName,L"FlowGPT recording",WS_POPUP,0,0,112,32,nullptr,nullptr,c.hInstance,nullptr);
        SetWindowLongPtrW(window_,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(this));
    }
    ~Hud(){KillTimer(window_,1);DestroyWindow(window_);if(graphicsToken_)Gdiplus::GdiplusShutdown(graphicsToken_);}
    void update(State state,double level){
        if(!busy(state)){active_=false;monitor_=nullptr;KillTimer(window_,1);ShowWindow(window_,SW_HIDE);return;}
        processing_=state!=State::recording;targetLevel_=std::clamp(level,0.0,1.0);
        if(!active_){active_=true;level_=targetLevel_;monitor_=MonitorFromWindow(GetForegroundWindow(),MONITOR_DEFAULTTONEAREST);position();draw();ShowWindow(window_,SW_SHOWNOACTIVATE);SetTimer(window_,1,33,nullptr);}
    }
    HWND handle()const{return window_;}
};
}
