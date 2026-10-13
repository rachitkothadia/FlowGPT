#include "AppController.h"
#include "Hud.h"
#include "NativeTests.h"
#undef GetCurrentTime
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>
#include <winrt/Windows.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.UI.h>
#include <microsoft.ui.xaml.window.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using namespace winrt::Microsoft::UI::Xaml::Media;
namespace {
constexpr UINT TrayMessage=WM_APP+3;
bool smokeLaunch=false;
void stage(const std::wstring& text){if(smokeLaunch)flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-stage.txt",text);}
struct App : ApplicationT<App,winrt::Microsoft::UI::Xaml::Markup::IXamlMetadataProvider> {
    winrt::Microsoft::UI::Xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider metadata{nullptr};
    Window window{nullptr};NavigationView navigation{nullptr};StackPanel content{nullptr};TextBlock status{nullptr};
    DispatcherTimer timer{nullptr};HWND hwnd{};NOTIFYICONDATAW tray{};HICON icon{};flow::Hud hud;
    std::unique_ptr<flow::AppController> controller;
    std::wstring page=L"Overview";bool background=false,preview=false,smoke=false;unsigned hotkeyChoice=0;double launched=flow::now();
    std::vector<std::pair<std::wstring,std::wstring>> devices;
    App(){stage(L"Application constructor");UnhandledException([](auto&&,auto&& e){if(smokeLaunch){flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-startup-error.txt",std::wstring(e.Message()));e.Handled(true);Application::Current().Exit();}});}
    auto provider(){if(!metadata)metadata=winrt::Microsoft::UI::Xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider();return metadata;}
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const& type){return provider().GetXamlType(type);}
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(hstring const& name){return provider().GetXamlType(name);}
    com_array<winrt::Microsoft::UI::Xaml::Markup::XmlnsDefinition> GetXmlnsDefinitions(){return provider().GetXmlnsDefinitions();}
    static TextBlock label(const std::wstring& value,double size=14){TextBlock t;t.Text(value);t.FontSize(size);t.TextWrapping(TextWrapping::Wrap);return t;}
    template<typename F> Button button(const std::wstring& text,F fn){Button b;b.Content(box_value(text));b.Click([fn](auto&&,auto&&){fn();});return b;}
    static SolidColorBrush green(){return SolidColorBrush(winrt::Windows::UI::Color{255,84,139,120});}
    void OnLaunched(LaunchActivatedEventArgs const&){
        stage(L"OnLaunched entered");
        Resources().MergedDictionaries().Append(XamlControlsResources());stage(L"Application resources ready");
        std::wstring args=GetCommandLineW();background=args.find(L"--background")!=std::wstring::npos;smoke=args.find(L"--ui-smoke")!=std::wstring::npos;preview=smoke||args.find(L"--design-preview")!=std::wstring::npos;
        window=Window();window.Title(L"FlowGPT");window.as<IWindowNative>()->get_WindowHandle(&hwnd);SetWindowSubclass(hwnd,procedure,1,reinterpret_cast<DWORD_PTR>(this));
        icon=flow::waveformIcon();SendMessageW(hwnd,WM_SETICON,ICON_SMALL,reinterpret_cast<LPARAM>(icon));SendMessageW(hwnd,WM_SETICON,ICON_BIG,reinterpret_cast<LPARAM>(icon));
        SetWindowPos(hwnd,nullptr,0,0,980,760,SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE);
        navigation=NavigationView();navigation.PaneDisplayMode(NavigationViewPaneDisplayMode::Left);navigation.OpenPaneLength(220);navigation.IsSettingsVisible(false);navigation.IsBackButtonVisible(NavigationViewBackButtonVisible::Collapsed);
        StackPanel brand;brand.Orientation(Orientation::Horizontal);brand.Spacing(12);brand.Margin({20,24,0,20});
        auto waveform=winrt::Microsoft::UI::Xaml::Markup::XamlReader::Load(L"<Path xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Data='M3,12 L3,18 M9,7 L9,23 M15,3 L15,27 M21,7 L21,23 M27,12 L27,18' Stroke='#548B78' StrokeThickness='3' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Width='30' Height='30'/> ").as<UIElement>();
        brand.Children().Append(waveform);brand.Children().Append(label(L"FlowGPT",23));navigation.PaneHeader(brand);
        for(auto name:{L"Overview",L"History",L"Settings"}){NavigationViewItem item;item.Content(box_value(name));item.Tag(box_value(name));SymbolIcon image;image.Symbol(name==std::wstring(L"Overview")?Symbol::Microphone:name==std::wstring(L"History")?Symbol::Clock:Symbol::Setting);item.Icon(image);navigation.MenuItems().Append(item);}
        navigation.SelectionChanged([this](auto&&,NavigationViewSelectionChangedEventArgs const& e){if(e.SelectedItem()){page=unbox_value<hstring>(e.SelectedItem().as<NavigationViewItem>().Tag());render();}});
        navigation.SelectedItem(navigation.MenuItems().GetAt(0));ScrollViewer scroll;content=StackPanel();content.Padding({32,28,32,28});content.Spacing(18);scroll.Content(content);navigation.Content(scroll);window.Content(navigation);
        try{window.SystemBackdrop(MicaBackdrop());}catch(...){/* Native theme is the fallback. */}
        controller=std::make_unique<flow::AppController>(hwnd,preview);controller->changed=[this]{render();hud.update(controller->session.state,controller->microphone.audio.level());};hud.finish=[this]{controller->finish();};
        hotkeyChoice=unsigned(controller->store.settings.GetNamedNumber(L"shortcut",0));if(hotkeyChoice>2)hotkeyChoice=0;registerHotkey();
        auto appearance=controller->store.settings.GetNamedString(L"appearance",L"System");navigation.RequestedTheme(appearance==L"Dark"?ElementTheme::Dark:appearance==L"Light"?ElementTheme::Light:ElementTheme::Default);
        tray.cbSize=sizeof(tray);tray.hWnd=hwnd;tray.uID=1;tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;tray.uCallbackMessage=TrayMessage;tray.hIcon=icon;wcscpy_s(tray.szTip,L"FlowGPT · Ctrl + Alt + Space");Shell_NotifyIconW(NIM_ADD,&tray);tray.uVersion=NOTIFYICON_VERSION_4;Shell_NotifyIconW(NIM_SETVERSION,&tray);
        timer=DispatcherTimer();timer.Interval(std::chrono::milliseconds(100));timer.Tick([this](auto&&,auto&&){controller->tick();renderStatus();hud.update(controller->session.state,controller->microphone.audio.level());if(smoke&&flow::now()-launched>12){flow::Json checks;checks.Insert(L"nativeWinUIWindowVisible",flow::JValue::CreateBooleanValue(IsWindowVisible(hwnd)!=FALSE));checks.Insert(L"historyFixtureLoaded",flow::JValue::CreateBooleanValue(controller->store.entries.size()==1));SendMessageW(hwnd,WM_CLOSE,0,0);checks.Insert(L"closeKeepsTrayResident",flow::JValue::CreateBooleanValue(IsWindow(hwnd)&&!IsWindowVisible(hwnd)));flow::Json report;report.Insert(L"checks",checks);bool pass=true;for(auto p:checks)pass=pass&&p.Value().GetBoolean();report.Insert(L"passed",flow::JValue::CreateBooleanValue(pass));flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-smoke.json",std::wstring(report.Stringify()));quit();}});timer.Start();render();
        window.Activate();stage(L"Window activated");if(background)ShowWindow(hwnd,SW_HIDE);
    }
    void registerHotkey(){UnregisterHotKey(hwnd,1);UINT key=hotkeyChoice==0?VK_SPACE:hotkeyChoice==1?'D':VK_F8;UINT modifiers=hotkeyChoice==2?MOD_CONTROL:MOD_CONTROL|MOD_ALT;controller->hotkeyReady=RegisterHotKey(hwnd,1,modifiers|MOD_NOREPEAT,key)!=FALSE;}
    static LRESULT CALLBACK procedure(HWND h,UINT m,WPARAM w,LPARAM l,UINT_PTR,DWORD_PTR data){auto self=reinterpret_cast<App*>(data);if(!self)return DefSubclassProc(h,m,w,l);
        if(m==WM_GETMINMAXINFO){auto limits=reinterpret_cast<MINMAXINFO*>(l);UINT dpi=GetDpiForWindow(h);limits->ptMinTrackSize={MulDiv(760,dpi,96),MulDiv(580,dpi,96)};return 0;}
        if(m==WM_CLOSE){ShowWindow(h,SW_HIDE);return 0;}
        if(m==WM_HOTKEY&&self->controller){self->controller->begin();return 0;}
        if(m==WM_POWERBROADCAST&&self->controller&&w==PBT_APMSUSPEND){if(flow::busy(self->controller->session.state))self->controller->cancel();return TRUE;}
        if(m==TrayMessage){UINT event=LOWORD(l);if(event==WM_LBUTTONUP||event==NIN_SELECT){self->show();return 0;}if(event==WM_CONTEXTMENU||event==WM_RBUTTONUP){HMENU menu=CreatePopupMenu();AppendMenuW(menu,MF_STRING,1,L"Start / finish dictation");AppendMenuW(menu,MF_STRING,2,L"History and settings");AppendMenuW(menu,MF_STRING,3,L"Connect ChatGPT");AppendMenuW(menu,MF_STRING,4,L"Quit FlowGPT");POINT p{};GetCursorPos(&p);SetForegroundWindow(h);int command=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,p.x,p.y,0,h,nullptr);DestroyMenu(menu);if(command==1)self->controller->begin(true);if(command==2)self->show();if(command==3)self->controller->browser.show();if(command==4)self->quit();return 0;}}
        if(m==RegisterWindowMessageW(L"TaskbarCreated")){Shell_NotifyIconW(NIM_ADD,&self->tray);return 0;}
        return DefSubclassProc(h,m,w,l);
    }
    void show(){ShowWindow(hwnd,SW_RESTORE);window.Activate();render();}
    void quit(){timer.Stop();controller->cancel();controller.reset();UnregisterHotKey(hwnd,1);Shell_NotifyIconW(NIM_DELETE,&tray);Exit();}
    void renderStatus(){if(!controller||!status)return;auto state=controller->session.state;auto text=flow::busy(state)||state!=flow::State::idle?controller->message:controller->browser.status;status.Text(text);}
    void copy(const std::wstring& text){if(!OpenClipboard(hwnd))return;HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(text.size()+1)*2);if(memory){void* p=GlobalLock(memory);if(p){memcpy(p,text.c_str(),(text.size()+1)*2);GlobalUnlock(memory);EmptyClipboard();if(!SetClipboardData(CF_UNICODETEXT,memory))GlobalFree(memory);}else GlobalFree(memory);}CloseClipboard();}
    void render(){if(!content||!controller)return;content.Children().Clear();content.Children().Append(label(page==L"Overview"?L"Speak. Keep your flow.":page==L"History"?L"Your words, saved.":L"Make yourself at home.",30));
        status=label(controller->message);status.Foreground(green());content.Children().Append(status);renderStatus();
        if(page==L"Overview"){
            content.Children().Append(label(L"Your words, right where you need them.",18));content.Children().Append(label(L"Press once to record. Press again to finish.",16));
            content.Children().Append(label(hotkeyChoice==0?L"Ctrl + Alt + Space":hotkeyChoice==1?L"Ctrl + Alt + D":L"Ctrl + F8",24));
            content.Children().Append(label(controller->hotkeyReady?L"✓ Global shortcut registered":L"Shortcut unavailable. Choose another in Settings."));
            content.Children().Append(button(L"Test dictation here",[this]{controller->begin(true);}));content.Children().Append(button(L"Cancel dictation",[this]{controller->cancel();}));
            content.Children().Append(label(L"This preview saves in History. To dictate into another app, focus its field and use your shortcut."));
            content.Children().Append(label(L"Recent dictations",20));for(size_t i=0;i<std::min<size_t>(3,controller->store.entries.size());++i)addEntry(controller->store.entries[i]);
        }else if(page==L"History"){
            TextBox search;search.PlaceholderText(L"Search your dictations");content.Children().Append(search);StackPanel list;list.Spacing(12);content.Children().Append(list);populateHistory(list,L"");
            search.TextChanged([this,search,list](auto&&,auto&&){populateHistory(list,std::wstring(search.Text()));});
            content.Children().Append(button(L"Clear history…",[this]{confirmClear();}));
        }else settings();
    }
    void addEntry(const flow::Entry& e,StackPanel list=nullptr){if(!list)list=content;Border card;card.CornerRadius({12});card.Padding({18,14,18,14});StackPanel inner;inner.Spacing(8);inner.Children().Append(label(e.date,12));TextBox text;text.Text(e.text);text.IsReadOnly(true);text.AcceptsReturn(true);text.TextWrapping(TextWrapping::Wrap);inner.Children().Append(text);StackPanel actions;actions.Orientation(Orientation::Horizontal);actions.Spacing(8);actions.Children().Append(button(L"Copy",[this,e]{copy(e.text);}));actions.Children().Append(button(L"Delete",[this,e]{try{controller->store.erase(e.id);render();}catch(...){controller->message=L"History deletion failed; original data retained";renderStatus();}}));inner.Children().Append(actions);card.Child(inner);list.Children().Append(card);}
    void populateHistory(StackPanel list,const std::wstring& query){list.Children().Clear();for(auto& e:controller->store.entries)if(query.empty()||e.text.find(query)!=std::wstring::npos)addEntry(e,list);if(!list.Children().Size())list.Children().Append(label(L"No matching dictations yet."));}
    fire_and_forget confirmClear(){ContentDialog dialog;dialog.XamlRoot(content.XamlRoot());dialog.Title(box_value(L"Clear local history?"));dialog.Content(box_value(L"This deletes your saved transcripts on this Windows account."));dialog.PrimaryButtonText(L"Clear history");dialog.CloseButtonText(L"Cancel");dialog.DefaultButton(ContentDialogButton::Close);auto answer=co_await dialog.ShowAsync();if(answer==ContentDialogResult::Primary){try{controller->store.persist({});render();}catch(...){controller->message=L"History could not be cleared";renderStatus();}}}
    void settings(){
        content.Children().Append(label(L"ChatGPT connection",20));content.Children().Append(label(L"Your website login is reused on this Windows account. Expired sessions need sign-in again."));
        content.Children().Append(button(L"Continue with ChatGPT / Manage connection",[this]{controller->browser.show();}));
        content.Children().Append(button(L"Reconnect when idle",[this]{controller->browser.reload();}));
        content.Children().Append(label(L"Microphone",20));ComboBox microphones;microphones.Items().Append(box_value(L"System default microphone"));
        try{devices=flow::microphones();for(auto& d:devices)microphones.Items().Append(box_value(d.second));}catch(...){devices.clear();}
        int selected=0;auto stored=controller->store.settings.GetNamedString(L"microphone",L"");for(size_t i=0;i<devices.size();++i)if(devices[i].first==stored)selected=int(i)+1;microphones.SelectedIndex(selected);
        microphones.SelectionChanged([this,microphones](auto&&,auto&&){int index=microphones.SelectedIndex();if(index<0||flow::busy(controller->session.state))return;try{controller->store.setting(L"microphone",flow::JValue::CreateStringValue(index==0?L"":devices[size_t(index-1)].first));}catch(...){controller->message=L"Microphone setting could not be saved";renderStatus();}});content.Children().Append(microphones);
        content.Children().Append(button(L"Open Windows microphone privacy",[]{ShellExecuteW(nullptr,L"open",L"ms-settings:privacy-microphone",nullptr,nullptr,SW_SHOWNORMAL);}));
        content.Children().Append(label(L"Microphone access is checked by real capture. Enable desktop microphone access in Windows Settings if recording is denied."));
        content.Children().Append(label(L"Keyboard shortcut",20));ComboBox shortcut;for(auto s:{L"Ctrl + Alt + Space",L"Ctrl + Alt + D",L"Ctrl + F8"})shortcut.Items().Append(box_value(s));shortcut.SelectedIndex(int(hotkeyChoice));shortcut.SelectionChanged([this,shortcut](auto&&,auto&&){if(shortcut.SelectedIndex()<0)return;hotkeyChoice=unsigned(shortcut.SelectedIndex());registerHotkey();try{controller->store.setting(L"shortcut",flow::JValue::CreateNumberValue(hotkeyChoice));}catch(...){controller->message=L"Shortcut preference could not be saved";}renderStatus();});content.Children().Append(shortcut);
        ToggleSwitch startup;startup.Header(box_value(L"Start FlowGPT when I sign in"));startup.IsOn(flow::startupEnabled());startup.Toggled([this,startup](auto&&,auto&&){try{flow::startup(startup.IsOn());}catch(...){controller->message=L"Windows startup registration failed";renderStatus();}});content.Children().Append(startup);
        content.Children().Append(label(L"Appearance",20));ComboBox theme;for(auto name:{L"System",L"Light",L"Dark"})theme.Items().Append(box_value(name));auto current=controller->store.settings.GetNamedString(L"appearance",L"System");theme.SelectedIndex(current==L"Light"?1:current==L"Dark"?2:0);theme.SelectionChanged([this,theme](auto&&,auto&&){int index=theme.SelectedIndex();if(index<0)return;navigation.RequestedTheme(index==1?ElementTheme::Light:index==2?ElementTheme::Dark:ElementTheme::Default);try{controller->store.setting(L"appearance",flow::JValue::CreateStringValue(index==1?L"Light":index==2?L"Dark":L"System"));}catch(...){controller->message=L"Appearance could not be saved";renderStatus();}});content.Children().Append(theme);
        content.Children().Append(button(L"Copy diagnostics",[this]{copy(controller->diagnostics());}));content.Children().Append(label(L"FlowGPT Windows 1.0.0 preview · Native C++ / WinUI 3\nAudio is sent to OpenAI through ChatGPT. Transcripts stay in local history. This experimental website bridge is not official OAuth or a speech API. Some protected or administrator apps restrict insertion."));
    }
};
}

int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int){
    if(std::wstring(GetCommandLineW()).find(L"--insertion-probe")!=std::wstring::npos){winrt::init_apartment(winrt::apartment_type::single_threaded);return flow::insertionProbe();}
    if(std::wstring(GetCommandLineW()).find(L"--self-test")!=std::wstring::npos){winrt::init_apartment(winrt::apartment_type::single_threaded);return flow::nativeTests();}
    HANDLE instance=CreateMutexW(nullptr,TRUE,L"Local\\FlowGPT.Windows.Instance");if(GetLastError()==ERROR_ALREADY_EXISTS){HWND existing=FindWindowW(nullptr,L"FlowGPT");if(existing){ShowWindow(existing,SW_RESTORE);SetForegroundWindow(existing);}if(instance)CloseHandle(instance);return 0;}
    smokeLaunch=std::wstring(GetCommandLineW()).find(L"--ui-smoke")!=std::wstring::npos;
    try{winrt::init_apartment(winrt::apartment_type::single_threaded);stage(L"Entering Application.Start");winrt::com_ptr<App> application;Application::Start([&application](auto&&){application=winrt::make_self<App>();});}
    catch(const winrt::hresult_error& e){if(smokeLaunch)flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-startup-error.txt",std::wstring(e.message()));else MessageBoxW(nullptr,e.message().c_str(),L"FlowGPT could not start",MB_ICONERROR);if(instance)CloseHandle(instance);return 1;}
    catch(...){MessageBoxW(nullptr,L"FlowGPT could not initialize. Reinstall the complete application and its runtimes.",L"FlowGPT",MB_ICONERROR);if(instance)CloseHandle(instance);return 1;}
    if(instance)CloseHandle(instance);return 0;
}
