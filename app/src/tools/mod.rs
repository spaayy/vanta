//! Vanta Tools: dados (catálogos, kit) e as telas.

mod app;
mod data;
mod kit;
mod optimize;
mod theme;

pub use app::{OpenSearch, ToolsApp};
pub use data::{Args, Edicao};

use gpui::{
    App, Bounds, TitlebarOptions, WindowBackgroundAppearance, WindowBounds, WindowOptions, prelude::*, px, size,
};

use crate::platform::application;
use crate::{assets, fonts, ui};

/// Abre o Vanta Tools da edição pedida. Os dois executáveis (`VantaTools` e `VantaToolsPublico`) só diferem nisto.
pub fn run(edicao: Edicao) {
    data::set_edicao(edicao);
    let args = Args::parse(edicao, std::env::args().skip(1));
    let app_id = match edicao {
        Edicao::Pessoal => "Vanta.Tools",
        Edicao::Publica => "Vanta.ToolsPublico",
    };
    application(false).with_assets(assets::Assets).run(move |cx: &mut App| {
        cx.bind_keys(ui::key_bindings());
        cx.bind_keys([gpui::KeyBinding::new("ctrl-k", OpenSearch, None)]);
        if let Err(error) = cx.text_system().add_fonts(fonts::embedded()) {
            log::warn!("Embedded fonts were not loaded: {error:#}");
        }
        cx.set_prompt_builder(ui::content_dialog::build);
        #[cfg(debug_assertions)]
        let initial_size = std::env::var("VANTA_TOOLS_PREVIEW_SIZE")
            .ok()
            .and_then(|raw| {
                let (w, h) = raw.split_once('x')?;
                Some((w.parse::<f32>().ok()?, h.parse::<f32>().ok()?))
            })
            .unwrap_or((1280., 820.));
        #[cfg(not(debug_assertions))]
        let initial_size = (1280., 820.);
        #[cfg(debug_assertions)]
        let preview_offscreen = std::env::var("VANTA_TOOLS_PREVIEW_OFFSCREEN").ok().as_deref() == Some("1");
        #[cfg(not(debug_assertions))]
        let preview_offscreen = false;
        let bounds = Bounds::centered(None, size(px(initial_size.0), px(initial_size.1)), cx);
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("Vanta Tools".into()),
                appears_transparent: true,
                traffic_light_position: None,
            }),
            window_background: WindowBackgroundAppearance::Opaque,
            window_min_size: Some(size(px(1000.), px(640.))),
            app_id: Some(app_id.into()),
            icon: assets::window_icon(),
            focus: !preview_offscreen,
            show: !preview_offscreen,
            ..Default::default()
        };
        let args = args.clone();
        cx.open_window(options, move |window, cx| {
            #[cfg(debug_assertions)]
            if preview_offscreen {
                use raw_window_handle::{HasWindowHandle, RawWindowHandle};
                use windows::Win32::Foundation::HWND;
                use windows::Win32::UI::WindowsAndMessaging::{
                    HWND_BOTTOM, SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_SHOWWINDOW, SetWindowPos,
                };
                window.resize(size(px(initial_size.0), px(initial_size.1)));
                if let Ok(handle) = HasWindowHandle::window_handle(window)
                    && let RawWindowHandle::Win32(win32) = handle.as_raw()
                {
                    let hwnd = HWND(win32.hwnd.get() as *mut core::ffi::c_void);
                    unsafe {
                        let _ = SetWindowPos(
                            hwnd,
                            Some(HWND_BOTTOM),
                            -20000,
                            0,
                            initial_size.0 as i32,
                            initial_size.1 as i32,
                            SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED,
                        );
                    }
                }
                window.resize(size(px(initial_size.0), px(initial_size.1)));
            }
            cx.new(|cx| ToolsApp::new(args, window, cx))
        })
        .expect("open the Vanta Tools window");
        cx.on_window_closed(|cx, _| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
        if !preview_offscreen {
            cx.activate(true);
        }
    });
}
