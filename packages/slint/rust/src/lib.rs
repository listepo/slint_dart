//! Renderer- and backend-agnostic core shared by every FFI crate.
//!
//! Holds only what both the interpreter path (`slint-dart-interpreter`) and
//! the compiled path (`slint-compiler-ffi`) need: mapping the FFI event
//! encoding (mirrored in Dart, see slint/lib/src/events.dart) onto
//! `slint::platform::WindowEvent`.

/// Thread affinity of everything behind the C ABIs.
///
/// Slint objects are `!Send` and each FFI crate keeps its error slot in a
/// thread-local, so a call from any thread but the first caller's is
/// undefined behaviour. Every entry point checks this first and reports an
/// error instead of corrupting state.
pub mod thread {
    use std::sync::OnceLock;
    use std::thread::ThreadId;

    static OWNER: OnceLock<ThreadId> = OnceLock::new();

    /// `Ok` on the thread that made the first call into this library, `Err`
    /// with a message for the error slot on any other.
    pub fn check() -> Result<(), String> {
        let me = std::thread::current().id();
        if *OWNER.get_or_init(|| me) == me {
            Ok(())
        } else {
            Err(
                "called from a thread other than the one that first used Slint; \
                 Slint is single-threaded, so drive a component only from the \
                 isolate that created it"
                    .into(),
            )
        }
    }
}

/// Event handling utilities for pointer and keyboard input.
pub mod events {
    use slint::platform::PointerEventButton;
    use slint::platform::WindowEvent;
    use slint::LogicalPosition;

    /// Create a pointer event from raw parameters.
    /// kind: 0=move, 1=down, 2=up, 3=scroll, 4=exit
    /// button: 0=none, 1=left, 2=right, 3=middle
    /// dx/dy: delta for scroll, movement for move
    pub fn pointer_event(
        kind: u8,
        x: f32,
        y: f32,
        button: u8,
        dx: f32,
        dy: f32,
    ) -> Option<WindowEvent> {
        let position = LogicalPosition::new(x, y);

        match kind {
            0 => Some(WindowEvent::PointerMoved { position }),
            1 => {
                let btn = match button {
                    1 => PointerEventButton::Left,
                    2 => PointerEventButton::Right,
                    3 => PointerEventButton::Middle,
                    _ => return None,
                };
                Some(WindowEvent::PointerPressed {
                    position,
                    button: btn,
                })
            }
            2 => {
                let btn = match button {
                    1 => PointerEventButton::Left,
                    2 => PointerEventButton::Right,
                    3 => PointerEventButton::Middle,
                    _ => return None,
                };
                Some(WindowEvent::PointerReleased {
                    position,
                    button: btn,
                })
            }
            3 => Some(WindowEvent::PointerScrolled {
                position,
                delta_x: dx,
                delta_y: dy,
            }),
            4 => Some(WindowEvent::PointerExited),
            _ => None,
        }
    }

    /// Create a keyboard event.
    pub fn key_event(text: &str, pressed: bool) -> WindowEvent {
        if pressed {
            WindowEvent::KeyPressed { text: text.into() }
        } else {
            WindowEvent::KeyReleased { text: text.into() }
        }
    }
}
