#ifndef WXTERMINALIME_H
#define WXTERMINALIME_H

/*
 * wxTerminalIME.h
 *
 * C-callable interface to the Objective-C++ IME helpers in wxTerminalIME.mm.
 * These fix two macOS-specific problems with wxTerminal:
 *
 * 1. IME candidate window position: wxWidgets' NSTextInputClient stub always
 *    returns a zero rect for firstRectForCharacterRange:, causing the Japanese
 *    (and other CJK) candidate window to appear at the top-left screen corner.
 *    We swizzle that method to return the real cursor position.
 *
 * 2. IME stops working after focus loss: The NSTextInputContext needs to be
 *    explicitly deactivated/reactivated when the window regains focus so that
 *    the IME state is properly reset.
 */

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Call once after the wxTerminal window is fully constructed.
 * Installs the method swizzle on wxNSView.
 */
void WxTerminalIME_Install(void);

/*
 * Call from setCursor() every time the logical cursor moves.
 * win       - the wxWindow* (cast to void* to keep header C-clean)
 * pixel_x   - cursor left edge in window client pixels
 * pixel_y   - cursor top  edge in window client pixels
 * char_h    - character cell height in pixels (used as rect height)
 */
void WxTerminalIME_UpdateCaretRect(void *win, int pixel_x, int pixel_y, int char_h);

/*
 * Call from OnFocus() when the terminal window regains focus.
 * Deactivates then reactivates the NSTextInputContext so the macOS IME
 * (e.g. Japanese Kana/Romaji) is properly re-initialized.
 * win - the wxWindow* cast to void*
 */
void WxTerminalIME_ResetInputContext(void *win);

#ifdef __cplusplus
}
#endif

#endif /* WXTERMINALIME_H */
