/*
 * wxTerminalIME.mm
 *
 * Objective-C++ fixes for macOS IME (Input Method Editor) support in
 * wxTerminal, which is a custom-drawn wxScrolledWindow.
 *
 * Problems fixed:
 *
 * 1. IME candidate window appears at top-left screen corner.
 *    Root cause: wxWidgets' NSTextInputClient stub implementation of
 *    firstRectForCharacterRange:actualRange: always returns NSZeroRect.
 *    The macOS IME reads this rect to position the candidate window, so
 *    it always falls back to (0,0) on screen.
 *    Fix: swizzle the method on wxNSView to return the real cursor rect
 *    in screen coordinates, which we update from C++ via
 *    WxTerminalIME_UpdateCaretRect().
 *
 * 2. Japanese IME stops working after switching to another app and back.
 *    Root cause: When the window regains focus, the NSTextInputContext is
 *    not reset, so the IME input source remains in a broken state.
 *    Fix: explicitly call [inputContext deactivate] + [inputContext activate]
 *    on the NSView's input context when focus is restored.
 *
 * Compile as part of the WX build only (guarded in Makefile.am).
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#ifdef HAVE_WX

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include "wxTerminalIME.h"

/* -----------------------------------------------------------------------
 * Global cursor rect in SCREEN coordinates.
 * Updated by WxTerminalIME_UpdateCaretRect() from C++ setCursor().
 * Read by the swizzled firstRectForCharacterRange:actualRange:.
 * ----------------------------------------------------------------------- */
static NSRect g_ime_cursor_screen_rect = NSZeroRect;

/* -----------------------------------------------------------------------
 * Swizzled implementation of
 *   - (NSRect)firstRectForCharacterRange:(NSRange)range
 *                           actualRange:(NSRangePointer)actualRange
 *
 * The original wxWidgets implementation returns NSZeroRect unconditionally,
 * which causes the IME candidate window to appear at the top-left corner
 * of the screen.  Our replacement returns g_ime_cursor_screen_rect.
 * ----------------------------------------------------------------------- */
static NSRect wxTerminal_firstRectForCharacterRange(id self,
                                                     SEL _cmd,
                                                     NSRange range,
                                                     NSRangePointer actualRange)
{
    (void)self; (void)_cmd; (void)range;
    if (actualRange)
        *actualRange = range;
    /* Return the stored screen-coordinate rect for the cursor.
       If it has never been set, return NSZeroRect (same as the original). */
    return g_ime_cursor_screen_rect;
}

/* -----------------------------------------------------------------------
 * WxTerminalIME_Install
 *
 * Swizzles firstRectForCharacterRange:actualRange: on wxNSView.
 * Must be called once after the wxTerminal window is created.
 * ----------------------------------------------------------------------- */
void WxTerminalIME_Install(void)
{
    /* wxWidgets names its backing NSView class "wxNSView" */
    Class cls = NSClassFromString(@"wxNSView");
    if (!cls) {
        /* Fallback: try the older name used in some wx versions */
        cls = NSClassFromString(@"wxNSPanel");
    }
    if (!cls)
        return;

    SEL sel = @selector(firstRectForCharacterRange:actualRange:);

    /* Build a method type encoding for:
     *   NSRect (id, SEL, NSRange, NSRangePointer)
     * We copy it from NSTextView which always has this method. */
    Method original = class_getInstanceMethod(cls, sel);
    if (!original)
        return;

    /* Replace the implementation. We don't need the original return value. */
    class_replaceMethod(cls,
                        sel,
                        (IMP)wxTerminal_firstRectForCharacterRange,
                        method_getTypeEncoding(original));
}

/* -----------------------------------------------------------------------
 * WxTerminalIME_UpdateCaretRect
 *
 * Called from wxTerminal::setCursor() every time the logical cursor moves.
 * Converts the client-coordinate cursor pixel position to screen coordinates
 * and stores it in g_ime_cursor_screen_rect for the swizzled method.
 * ----------------------------------------------------------------------- */
void WxTerminalIME_UpdateCaretRect(void *win_ptr, int pixel_x, int pixel_y, int char_h)
{
    if (!win_ptr)
        return;

    /* win_ptr is a wxWindow*; get its underlying NSView via GetHandle(). */
#ifdef __cplusplus
    /* Include just enough to use GetHandle(). We keep this block in an
     * extern "C" wrapper in the header so the .cpp caller doesn't need
     * Objective-C headers. */
    {
        /* Cast to NSView* — wxWindow::GetHandle() returns the NSView* on OSX */
        NSView *view = (NSView *)win_ptr;

        /* Build the cursor rect in view (client) coordinates.
         * pixel_y is already in scrolled client coordinates (scroll offset
         * has been subtracted by the caller). */
        NSRect client_rect = NSMakeRect((CGFloat)pixel_x,
                                        /* Cocoa Y is flipped vs wx:
                                         * wx origin = top-left,
                                         * Cocoa origin = bottom-left.
                                         * Convert: cocoa_y = view.height - wx_y - char_h */
                                        [view bounds].size.height - (CGFloat)pixel_y - (CGFloat)char_h,
                                        1.0,
                                        (CGFloat)char_h);

        /* Convert to screen coordinates. */
        NSRect window_rect = [view convertRect:client_rect toView:nil];
        NSRect screen_rect = [[view window] convertRectToScreen:window_rect];

        g_ime_cursor_screen_rect = screen_rect;

        /* Tell the active input context that the character coordinates have
         * changed so it re-queries firstRectForCharacterRange: immediately. */
        NSTextInputContext *ctx = [NSTextInputContext currentInputContext];
        if (ctx)
            [ctx invalidateCharacterCoordinates];
    }
#endif
}

/* -----------------------------------------------------------------------
 * WxTerminalIME_ResetInputContext
 *
 * Called from wxTerminal::OnFocus() when the window regains focus.
 * Deactivates then reactivates the NSTextInputContext so the macOS IME
 * input source (e.g. Japanese Kana) is properly re-initialized.
 *
 * Without this, switching to another application and back leaves the IME
 * in a broken state where key events are not forwarded to the input method.
 * ----------------------------------------------------------------------- */
void WxTerminalIME_ResetInputContext(void *win_ptr)
{
    if (!win_ptr)
        return;

    NSView *view = (NSView *)win_ptr;

    /* Activate the view's input context.  The deactivate/activate cycle
     * forces the IME to reinitialize its internal state for this view. */
    NSTextInputContext *ctx = [view inputContext];
    if (ctx) {
        [ctx deactivate];
        [ctx activate];
    }
}

#endif /* HAVE_WX */
