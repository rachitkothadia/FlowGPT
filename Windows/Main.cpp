#include "AppController.h"
#include "Hud.h"
#include "NativeTests.h"
#include "Updates.h"
#undef GetCurrentTime
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>
#include <winrt/Windows.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
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
    Window window{nullptr};NavigationView navigation{nullptr};StackPanel content{nullptr};TextBlock status{nullptr},updateStatus{nullptr};
    Button updateAction{nullptr};
    DispatcherTimer timer{nullptr};HWND hwnd{};NOTIFYICONDATAW tray{};HICON icon{};flow::Hud hud;flow::Updates updates;
    std::unique_ptr<flow::AppController> controller;
    std::wstring page=L"Home";bool background=false,preview=false,smoke=false,quitting=false,trayReady=false;unsigned hotkeyChoice=0;double launched=flow::now();
    std::vector<std::pair<std::wstring,std::wstring>> devices;
    flow::Json uiChecks;int smokePhase=0;double smokeNext=0;TextBox searchBox{nullptr};StackPanel historyList{nullptr};
    App(){
        UnhandledException([this](auto&&,auto&& e){
            try{if(smokeLaunch)flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-startup-error.txt",std::wstring(e.Message()));
                if(controller){controller->lastError=E_FAIL;controller->fail(L"A window operation failed. Your saved text is safe in History.");e.Handled(true);}}
            catch(...){}
        });
    }
    auto provider(){if(!metadata)metadata=winrt::Microsoft::UI::Xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider();return metadata;}
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const& type){return provider().GetXamlType(type);}
    winrt::Microsoft::UI::Xaml::Markup::IXamlType GetXamlType(hstring const& name){return provider().GetXamlType(name);}
    com_array<winrt::Microsoft::UI::Xaml::Markup::XmlnsDefinition> GetXmlnsDefinitions(){return provider().GetXmlnsDefinitions();}
    void recover(long code)noexcept{try{if(controller){controller->lastError=code;controller->fail(L"An operation failed. Your saved text remains in History.");}hud.update(flow::State::error,0);}catch(...){}}
    template<typename F>void safely(F fn)noexcept{try{fn();}catch(const hresult_error& e){recover(e.code().value);}catch(...){recover(E_FAIL);}}
    static TextBlock label(const std::wstring& value,double size=14,bool muted=false){
        TextBlock t;t.Text(value);t.FontSize(size);t.TextWrapping(TextWrapping::Wrap);if(muted)t.Opacity(0.68);return t;
    }
    static TextBlock heading(const std::wstring& value,double size=28){auto t=label(value,size);t.FontWeight(winrt::Windows::UI::Text::FontWeight{600});return t;}
    static SolidColorBrush green(){return SolidColorBrush(winrt::Windows::UI::Color{255,84,139,120});}
    template<typename F>Button button(const std::wstring& text,F fn,bool accent=false){
        Button b;b.Content(box_value(text));b.Padding({16,10,16,10});if(accent){b.Background(green());b.Foreground(SolidColorBrush(winrt::Windows::UI::Color{255,255,255,255}));}
        b.Click([this,fn](auto&&,auto&&){safely(fn);});return b;
    }
    std::wstring shortcutText()const{const wchar_t* values[]{L"Ctrl + Alt + Space",L"Ctrl + Alt + D",L"Ctrl + F8",L"Ctrl + Space"};return values[std::min(hotkeyChoice,3u)];}
    bool busy()const{return controller&&flow::busy(controller->session.state);}
    void addTray(){
        tray.cbSize=sizeof(tray);tray.hWnd=hwnd;tray.uID=1;tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP|NIF_SHOWTIP;tray.uCallbackMessage=TrayMessage;tray.hIcon=icon;
        wcscpy_s(tray.szTip,L"FlowGPT");trayReady=Shell_NotifyIconW(NIM_ADD,&tray)!=FALSE;
        if(trayReady){tray.uVersion=NOTIFYICON_VERSION_4;Shell_NotifyIconW(NIM_SETVERSION,&tray);}
    }
    void hide(){if(trayReady)window.AppWindow().Hide();else if(controller){controller->message=L"Background icon is unavailable. Keep this window open or restart FlowGPT.";renderStatus();}}
    void OnLaunched(LaunchActivatedEventArgs const&){
        stage(L"OnLaunched entered");Resources().MergedDictionaries().Append(XamlControlsResources());
        std::wstring args=GetCommandLineW();background=args.find(L"--background")!=std::wstring::npos;smoke=args.find(L"--ui-smoke")!=std::wstring::npos;preview=smoke||args.find(L"--design-preview")!=std::wstring::npos;
        window=Window();window.Title(L"FlowGPT");window.as<IWindowNative>()->get_WindowHandle(&hwnd);
        SetWindowSubclass(hwnd,procedure,1,reinterpret_cast<DWORD_PTR>(this));
        window.AppWindow().Closing([this](auto&&,winrt::Microsoft::UI::Windowing::AppWindowClosingEventArgs const& e){if(!quitting){e.Cancel(true);safely([this]{hide();});}});
        icon=flow::waveformIcon();SendMessageW(hwnd,WM_SETICON,ICON_SMALL,reinterpret_cast<LPARAM>(icon));SendMessageW(hwnd,WM_SETICON,ICON_BIG,reinterpret_cast<LPARAM>(icon));
        MONITORINFO monitor{sizeof(monitor)};GetMonitorInfoW(MonitorFromWindow(hwnd,MONITOR_DEFAULTTONEAREST),&monitor);UINT dpi=GetDpiForWindow(hwnd);
        int width=std::min(MulDiv(880,dpi,96),int(monitor.rcWork.right-monitor.rcWork.left)-40),height=std::min(MulDiv(650,dpi,96),int(monitor.rcWork.bottom-monitor.rcWork.top)-40);
        SetWindowPos(hwnd,nullptr,monitor.rcWork.left+(monitor.rcWork.right-monitor.rcWork.left-width)/2,monitor.rcWork.top+(monitor.rcWork.bottom-monitor.rcWork.top-height)/2,width,height,SWP_NOZORDER|SWP_NOACTIVATE);
        navigation=NavigationView();navigation.PaneDisplayMode(NavigationViewPaneDisplayMode::Left);navigation.OpenPaneLength(196);navigation.IsSettingsVisible(false);navigation.IsBackButtonVisible(NavigationViewBackButtonVisible::Collapsed);
        StackPanel brand;brand.Orientation(Orientation::Horizontal);brand.Spacing(10);brand.Margin({18,20,0,20});
        auto mark=winrt::Microsoft::UI::Xaml::Markup::XamlReader::Load(L"<Path xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Data='M3,12 L3,18 M9,7 L9,23 M15,3 L15,27 M21,7 L21,23 M27,12 L27,18' Stroke='#548B78' StrokeThickness='3' StrokeStartLineCap='Round' StrokeEndLineCap='Round' Width='30' Height='30'/>").as<UIElement>();
        brand.Children().Append(mark);brand.Children().Append(heading(L"FlowGPT",20));navigation.PaneHeader(brand);
        for(auto name:{L"Home",L"History",L"Settings",L"About"}){
            NavigationViewItem item;item.Content(box_value(name));item.Tag(box_value(name));SymbolIcon image;
            image.Symbol(name==std::wstring(L"Home")?Symbol::Home:name==std::wstring(L"History")?Symbol::Clock:name==std::wstring(L"Settings")?Symbol::Setting:Symbol::Help);item.Icon(image);navigation.MenuItems().Append(item);
        }
        navigation.SelectionChanged([this](auto&&,NavigationViewSelectionChangedEventArgs const& e){safely([&]{if(e.SelectedItem()){page=unbox_value<hstring>(e.SelectedItem().as<NavigationViewItem>().Tag());render();}});});
        ScrollViewer scroll;content=StackPanel();content.Padding({30,24,30,24});content.Spacing(16);content.MaxWidth(760);scroll.Content(content);navigation.Content(scroll);window.Content(navigation);
        try{window.SystemBackdrop(MicaBackdrop());}catch(...){}
        controller=std::make_unique<flow::AppController>(hwnd,preview);
        controller->changed=[this]{if(quitting)return;render();hud.update(controller->session.state,controller->microphone.audio.level());};
        hud.finish=[this]{safely([this]{if(controller)controller->finish();});};
        hotkeyChoice=unsigned(controller->store.settings.GetNamedNumber(L"shortcut",0));if(hotkeyChoice>3)hotkeyChoice=0;registerHotkey();
        auto appearance=controller->store.settings.GetNamedString(L"appearance",L"System");navigation.RequestedTheme(appearance==L"Dark"?ElementTheme::Dark:appearance==L"Light"?ElementTheme::Light:ElementTheme::Default);
        addTray();navigation.SelectedItem(navigation.MenuItems().GetAt(0));
        timer=DispatcherTimer();timer.Interval(std::chrono::milliseconds(50));timer.Tick([this](auto&&,auto&&){
            safely([this]{if(!controller||quitting)return;controller->tick();renderStatus();hud.update(controller->session.state,controller->microphone.audio.level());renderUpdates();if(smoke&&flow::now()-launched>12)verifyUI();});
        });timer.Start();render();window.Activate();stage(L"Window activated");if(background)hide();
    }
    void registerHotkey(){
        UnregisterHotKey(hwnd,1);UINT key=hotkeyChoice==1?'D':hotkeyChoice==2?VK_F8:VK_SPACE;
        UINT modifiers=hotkeyChoice>=2?MOD_CONTROL:MOD_CONTROL|MOD_ALT;controller->hotkeyReady=RegisterHotKey(hwnd,1,modifiers|MOD_NOREPEAT,key)!=FALSE;
    }
    void verifyUI(){
        if(flow::now()<smokeNext)return;auto check=[&](const wchar_t* name,bool good){uiChecks.Insert(name,flow::JValue::CreateBooleanValue(good));};
        if(smokePhase==0){
            check(background?L"startupWindowHidden":L"nativeWinUIWindowVisible",background?!IsWindowVisible(hwnd):IsWindowVisible(hwnd)!=FALSE);
            check(L"historyFixtureLoaded",controller->store.entries.size()==1);check(L"shortcutRegisteredInApp",controller->hotkeyReady);check(L"trayIconRegistered",trayReady);
            navigation.SelectedItem(navigation.MenuItems().GetAt(1));check(L"historyPageRenders",page==L"History"&&searchBox&&historyList);
            searchBox.Text(L"PROJECT");smokePhase=1;smokeNext=flow::now()+0.2;return;
        }
        if(smokePhase==1){check(L"historySearchIgnoresEnglishCase",historyList.Children().Size()==1&&historyList.Children().GetAt(0).try_as<Border>());searchBox.Text(L"no-such-phrase");smokePhase=2;smokeNext=flow::now()+0.2;return;}
        check(L"historySearchEmptyState",historyList.Children().Size()==1&&historyList.Children().GetAt(0).try_as<TextBlock>());
        navigation.SelectedItem(navigation.MenuItems().GetAt(2));check(L"settingsPageRenders",page==L"Settings"&&content.Children().Size()>8);
        navigation.SelectedItem(navigation.MenuItems().GetAt(3));check(L"aboutUpdateCheckVisible",page==L"About"&&updateAction);
        hotkeyChoice=3;registerHotkey();check(L"ctrlSpaceShortcutRegistered",controller->hotkeyReady);hotkeyChoice=0;registerHotkey();
        navigation.RequestedTheme(ElementTheme::Dark);check(L"darkThemeApplied",navigation.RequestedTheme()==ElementTheme::Dark);navigation.RequestedTheme(ElementTheme::Light);check(L"lightThemeApplied",navigation.RequestedTheme()==ElementTheme::Light);
        controller->changed=[]{throw std::runtime_error("Injected presentation error");};controller->cancel();check(L"presentationFailureContained",controller->lastError==E_FAIL);controller->changed=[this]{if(!quitting)render();};
        SendMessageW(hwnd,WM_SYSCOMMAND,SC_CLOSE,0);check(L"titleBarCloseKeepsTrayResident",!IsWindowVisible(hwnd)&&controller!=nullptr);show();check(L"hiddenWindowReopens",IsWindowVisible(hwnd)!=FALSE);
        flow::Json report;report.Insert(L"checks",uiChecks);bool pass=true;for(auto p:uiChecks)pass=pass&&p.Value().GetBoolean();report.Insert(L"passed",flow::JValue::CreateBooleanValue(pass));
        flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-smoke.json",std::wstring(report.Stringify()));quit();
    }
    static LRESULT CALLBACK procedure(HWND h,UINT m,WPARAM w,LPARAM l,UINT_PTR,DWORD_PTR data){
        auto self=reinterpret_cast<App*>(data);if(!self)return DefSubclassProc(h,m,w,l);
        if(m==WM_GETMINMAXINFO){auto limits=reinterpret_cast<MINMAXINFO*>(l);UINT dpi=GetDpiForWindow(h);limits->ptMinTrackSize={MulDiv(680,dpi,96),MulDiv(480,dpi,96)};return 0;}
        if((m==WM_CLOSE||(m==WM_SYSCOMMAND&&(w&0xfff0)==SC_CLOSE))&&!self->quitting){self->safely([self]{self->hide();});return 0;}
        if(m==WM_HOTKEY&&self->controller){self->safely([self]{self->controller->begin();});return 0;}
        if(m==WM_POWERBROADCAST&&self->controller&&w==PBT_APMSUSPEND){self->safely([self]{if(self->busy())self->controller->cancel();});return TRUE;}
        if(m==TrayMessage){
            self->safely([&]{UINT event=LOWORD(l);if(event==WM_LBUTTONUP||event==NIN_SELECT){self->show();return;}
                if(event==WM_CONTEXTMENU||event==WM_RBUTTONUP){HMENU menu=CreatePopupMenu();AppendMenuW(menu,MF_STRING,1,L"Open FlowGPT");AppendMenuW(menu,MF_STRING,2,L"Start / finish dictation");AppendMenuW(menu,MF_STRING,3,L"Connect ChatGPT");AppendMenuW(menu,MF_STRING,4,L"Quit FlowGPT");POINT p{};GetCursorPos(&p);SetForegroundWindow(h);int command=TrackPopupMenu(menu,TPM_RETURNCMD|TPM_RIGHTBUTTON,p.x,p.y,0,h,nullptr);DestroyMenu(menu);
                    if(command==1)self->show();if(command==2&&self->controller)self->controller->begin(true);if(command==3&&self->controller)self->controller->browser.show();if(command==4)self->quit();}});
            return 0;
        }
        if(m==RegisterWindowMessageW(L"TaskbarCreated")){self->safely([self]{self->addTray();});return 0;}
        return DefSubclassProc(h,m,w,l);
    }
    void show(){window.AppWindow().Show();window.Activate();render();}
    void quit(){if(quitting)return;quitting=true;if(timer)timer.Stop();hud.update(flow::State::finished,0);if(controller){controller->cancel();controller.reset();}UnregisterHotKey(hwnd,1);Shell_NotifyIconW(NIM_DELETE,&tray);Exit();}
    void renderStatus(){if(!controller||!status)return;auto state=controller->session.state;status.Text(flow::busy(state)||state!=flow::State::idle?controller->message:controller->browser.status);}
    void copy(const std::wstring& text){
        if(!OpenClipboard(hwnd))return;HGLOBAL memory=GlobalAlloc(GMEM_MOVEABLE,(text.size()+1)*sizeof(wchar_t));
        if(memory){void* p=GlobalLock(memory);if(p){memcpy(p,text.c_str(),(text.size()+1)*sizeof(wchar_t));GlobalUnlock(memory);EmptyClipboard();if(!SetClipboardData(CF_UNICODETEXT,memory))GlobalFree(memory);}else GlobalFree(memory);}CloseClipboard();
    }
    void render(){
        if(!content||!controller||quitting)return;content.Children().Clear();status=nullptr;updateStatus=nullptr;updateAction=nullptr;searchBox=nullptr;historyList=nullptr;
        content.Children().Append(heading(page==L"Home"?L"Dictate, then keep going.":page==L"History"?L"Your history":page==L"Settings"?L"Settings":L"About FlowGPT"));
        status=label(controller->message,14,true);content.Children().Append(status);renderStatus();
        if(page==L"Home"){
            auto shortcut=heading(shortcutText(),25);shortcut.Margin({0,12,0,0});content.Children().Append(shortcut);
            content.Children().Append(label(L"Press once to start. Press again to finish.",15,true));
            if(!controller->hotkeyReady)content.Children().Append(label(L"This shortcut is unavailable. Choose another in Settings."));
            bool recording=controller->session.state==flow::State::starting||controller->session.state==flow::State::recording;
            if(controller->browser.connected||recording){auto start=button(recording?L"Finish dictation":L"Try dictation",[this]{controller->begin(true);},true);start.IsEnabled(!busy()||recording);content.Children().Append(start);}
            else content.Children().Append(button(L"Connect ChatGPT",[this]{controller->browser.show();},true));
            content.Children().Append(label(L"To write in another app, click its text area and use your shortcut. FlowGPT stays near the clock when you close this window.",14,true));
            if(busy())content.Children().Append(button(L"Cancel",[this]{controller->cancel();}));
            content.Children().Append(heading(L"Last dictation",17));
            if(controller->store.entries.empty())content.Children().Append(label(L"Your first dictation will appear here.",14,true));
            else{auto text=label(controller->store.entries.front().text,15);text.MaxLines(5);text.TextTrimming(TextTrimming::CharacterEllipsis);text.IsTextSelectionEnabled(true);content.Children().Append(text);
                content.Children().Append(button(L"View history",[this]{navigation.SelectedItem(navigation.MenuItems().GetAt(1));}));}
        }else if(page==L"History"){
            searchBox=TextBox();searchBox.PlaceholderText(L"Search your dictations");content.Children().Append(searchBox);historyList=StackPanel();historyList.Spacing(12);content.Children().Append(historyList);populateHistory(historyList,L"");
            auto search=searchBox;auto list=historyList;search.TextChanged([this,search,list](auto&&,auto&&){safely([&]{populateHistory(list,std::wstring(search.Text()));});});
            content.Children().Append(button(L"Clear history…",[this]{confirmClear();}));
        }else if(page==L"Settings")settings();else about();
    }
    void addEntry(const flow::Entry& e,StackPanel list){
        Border card;card.CornerRadius({10});card.Padding({16,12,16,12});StackPanel inner;inner.Spacing(10);inner.Children().Append(label(e.date,12,true));
        TextBox text;text.Text(e.text);text.IsReadOnly(true);text.AcceptsReturn(true);text.TextWrapping(TextWrapping::Wrap);text.MinHeight(90);text.MaxHeight(240);ScrollViewer::SetVerticalScrollBarVisibility(text,ScrollBarVisibility::Auto);inner.Children().Append(text);
        StackPanel actions;actions.Orientation(Orientation::Horizontal);actions.Spacing(8);actions.Children().Append(button(L"Copy",[this,e]{copy(e.text);}));
        if(!e.raw.empty()&&e.raw!=e.text)actions.Children().Append(button(L"Copy original",[this,e]{copy(e.raw);}));
        actions.Children().Append(button(L"Delete",[this,e]{controller->store.erase(e.id);render();}));inner.Children().Append(actions);card.Child(inner);list.Children().Append(card);
    }
    void populateHistory(StackPanel list,const std::wstring& query){
        list.Children().Clear();for(const auto& e:controller->store.entries)if(query.empty()||FindNLSStringEx(LOCALE_NAME_INVARIANT,FIND_FROMSTART|NORM_IGNORECASE,e.text.c_str(),int(e.text.size()),query.c_str(),int(query.size()),nullptr,nullptr,nullptr,0)>=0)addEntry(e,list);
        if(!list.Children().Size())list.Children().Append(label(L"No matching dictations.",14,true));
    }
    fire_and_forget confirmClear(){
        try{ContentDialog dialog;dialog.XamlRoot(content.XamlRoot());dialog.Title(box_value(L"Clear history?"));dialog.Content(box_value(L"This deletes the dictations saved on this computer."));dialog.PrimaryButtonText(L"Clear history");dialog.CloseButtonText(L"Cancel");dialog.DefaultButton(ContentDialogButton::Close);
            auto answer=co_await dialog.ShowAsync();if(answer==ContentDialogResult::Primary&&controller&&!quitting){controller->store.persist({});render();}}
        catch(...){recover(E_FAIL);}
    }
    void settings(){
        content.Children().Append(heading(L"Connection",17));content.Children().Append(label(L"Use your own ChatGPT account. Sign in again if your session expires.",14,true));
        auto connect=button(L"Manage connection",[this]{controller->browser.show();});connect.IsEnabled(!busy());content.Children().Append(connect);
        auto reconnect=button(L"Reconnect",[this]{controller->browser.reload();});reconnect.IsEnabled(!busy());content.Children().Append(reconnect);
        content.Children().Append(heading(L"Microphone",17));ComboBox inputs;inputs.HorizontalAlignment(HorizontalAlignment::Stretch);inputs.Items().Append(box_value(L"System default"));
        try{devices=flow::microphones();for(auto& d:devices)inputs.Items().Append(box_value(d.second));}catch(...){devices.clear();}
        int selected=0;auto stored=controller->store.settings.GetNamedString(L"microphone",L"");for(size_t i=0;i<devices.size();++i)if(devices[i].first==stored)selected=int(i)+1;inputs.SelectedIndex(selected);inputs.IsEnabled(!busy());
        inputs.SelectionChanged([this,inputs](auto&&,auto&&){safely([&]{int index=inputs.SelectedIndex();if(index<0||busy())return;controller->store.setting(L"microphone",flow::JValue::CreateStringValue(index==0?L"":devices[size_t(index-1)].first));});});content.Children().Append(inputs);
        content.Children().Append(button(L"Microphone permissions",[]{ShellExecuteW(nullptr,L"open",L"ms-settings:privacy-microphone",nullptr,nullptr,SW_SHOWNORMAL);}));
        content.Children().Append(heading(L"Shortcut",17));ComboBox shortcut;for(auto s:{L"Ctrl + Alt + Space",L"Ctrl + Alt + D",L"Ctrl + F8",L"Ctrl + Space"})shortcut.Items().Append(box_value(s));shortcut.SelectedIndex(int(hotkeyChoice));shortcut.IsEnabled(!busy());
        shortcut.SelectionChanged([this,shortcut](auto&&,auto&&){safely([&]{if(shortcut.SelectedIndex()<0||busy())return;hotkeyChoice=unsigned(shortcut.SelectedIndex());registerHotkey();controller->store.setting(L"shortcut",flow::JValue::CreateNumberValue(hotkeyChoice));renderStatus();});});content.Children().Append(shortcut);
        ToggleSwitch startup;startup.Header(box_value(L"Start FlowGPT when I sign in"));startup.IsOn(flow::startupEnabled());startup.Toggled([this,startup](auto&&,auto&&){safely([&]{flow::startup(startup.IsOn());});});content.Children().Append(startup);
        content.Children().Append(button(L"Windows startup settings",[]{ShellExecuteW(nullptr,L"open",L"ms-settings:startupapps",nullptr,nullptr,SW_SHOWNORMAL);}));
        ToggleSwitch format;format.Header(box_value(L"Format explicit numbered lists"));format.IsOn(controller->store.settings.GetNamedBoolean(L"readableFormatting",true));format.Toggled([this,format](auto&&,auto&&){safely([&]{controller->store.setting(L"readableFormatting",flow::JValue::CreateBooleanValue(format.IsOn()));});});content.Children().Append(format);
        content.Children().Append(label(L"Preserves words, repetitions, languages and scripts. The original text stays in History.",13,true));
        content.Children().Append(heading(L"Appearance",17));ComboBox theme;for(auto name:{L"System",L"Light",L"Dark"})theme.Items().Append(box_value(name));auto current=controller->store.settings.GetNamedString(L"appearance",L"System");theme.SelectedIndex(current==L"Light"?1:current==L"Dark"?2:0);
        theme.SelectionChanged([this,theme](auto&&,auto&&){safely([&]{int index=theme.SelectedIndex();if(index<0)return;navigation.RequestedTheme(index==1?ElementTheme::Light:index==2?ElementTheme::Dark:ElementTheme::Default);controller->store.setting(L"appearance",flow::JValue::CreateStringValue(index==1?L"Light":index==2?L"Dark":L"System"));});});content.Children().Append(theme);
    }
    void about(){
        content.Children().Append(heading(L"Version 1.1.0 · Windows preview",18));
        content.Children().Append(label(L"Speak into your ChatGPT connection. Your dictations are saved on this computer.",14,true));
        content.Children().Append(heading(L"Updates",17));updateStatus=label(updates.state().message);content.Children().Append(updateStatus);
        updateAction=button(L"Check for updates",[this]{auto state=updates.state();if(busy())return;if(state.downloaded){if(updates.install(hwnd))quit();}else if(state.available)updates.download();else updates.check();});content.Children().Append(updateAction);renderUpdates();
        content.Children().Append(button(L"Copy diagnostics",[this]{copy(controller->diagnostics());}));
        content.Children().Append(label(L"This preview is unsigned. ChatGPT connection limits and website changes can affect dictation.",13,true));
        content.Children().Append(button(L"Installation help",[]{ShellExecuteW(nullptr,L"open",L"https://github.com/rachitkothadia/FlowGPT#installation",nullptr,nullptr,SW_SHOWNORMAL);}));
    }
    void renderUpdates(){if(!updateStatus||!updateAction)return;auto s=updates.state();updateStatus.Text(s.message);updateAction.Content(box_value(s.downloaded?L"Install update":s.available?L"Download update":L"Check for updates"));updateAction.IsEnabled(!s.busy&&!busy());}
};
}
int WINAPI wWinMain(HINSTANCE,HINSTANCE,PWSTR,int){
    if(std::wstring(GetCommandLineW()).find(L"--insertion-probe")!=std::wstring::npos){winrt::init_apartment(winrt::apartment_type::single_threaded);return flow::insertionProbe();}
    if(std::wstring(GetCommandLineW()).find(L"--self-test")!=std::wstring::npos){winrt::init_apartment(winrt::apartment_type::single_threaded);return flow::nativeTests();}
    HANDLE instance=CreateMutexW(nullptr,TRUE,L"Local\\FlowGPT.Windows.Instance");if(GetLastError()==ERROR_ALREADY_EXISTS){HWND existing=FindWindowW(nullptr,L"FlowGPT");if(existing){ShowWindow(existing,SW_RESTORE);SetForegroundWindow(existing);}if(instance)CloseHandle(instance);return 0;}
    smokeLaunch=std::wstring(GetCommandLineW()).find(L"--ui-smoke")!=std::wstring::npos;
    try{winrt::init_apartment(winrt::apartment_type::single_threaded);stage(L"Entering Application.Start");winrt::com_ptr<App> app;Application::Start([&app](auto&&){app=winrt::make_self<App>();});}
    catch(const winrt::hresult_error& e){if(smokeLaunch)flow::atomicWrite(std::filesystem::path(flow::exePath()).parent_path()/L"ui-startup-error.txt",std::wstring(e.message()));else MessageBoxW(nullptr,e.message().c_str(),L"FlowGPT could not start",MB_ICONERROR);if(instance)CloseHandle(instance);return 1;}
    catch(...){MessageBoxW(nullptr,L"FlowGPT could not start. Reinstall the complete application.",L"FlowGPT",MB_ICONERROR);if(instance)CloseHandle(instance);return 1;}
    if(instance)CloseHandle(instance);return 0;
}
