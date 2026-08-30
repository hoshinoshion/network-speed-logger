using System.Runtime.InteropServices;

namespace NetworkSpeedLogger;

internal sealed class InputMethodSnapshot
{
    private readonly nint _keyboardLayout;
    private readonly bool _hasImeState;
    private readonly bool _hasConversionState;
    private readonly bool _imeOpen;
    private readonly uint _conversionMode;
    private readonly uint _sentenceMode;

    private InputMethodSnapshot(
        nint keyboardLayout,
        bool hasImeState,
        bool hasConversionState,
        bool imeOpen,
        uint conversionMode,
        uint sentenceMode)
    {
        _keyboardLayout = keyboardLayout;
        _hasImeState = hasImeState;
        _hasConversionState = hasConversionState;
        _imeOpen = imeOpen;
        _conversionMode = conversionMode;
        _sentenceMode = sentenceMode;
    }

    public static InputMethodSnapshot CaptureForeground()
    {
        nint foregroundWindow = GetForegroundWindow();
        uint foregroundThread = foregroundWindow == 0
            ? 0
            : GetWindowThreadProcessId(foregroundWindow, out _);
        nint keyboardLayout = foregroundThread == 0 ? 0 : GetKeyboardLayout(foregroundThread);

        if (foregroundWindow == 0)
            return new InputMethodSnapshot(keyboardLayout, false, false, false, 0, 0);

        nint inputContext = ImmGetContext(foregroundWindow);
        if (inputContext == 0)
            return new InputMethodSnapshot(keyboardLayout, false, false, false, 0, 0);

        try
        {
            bool imeOpen = ImmGetOpenStatus(inputContext);
            bool hasConversionState = ImmGetConversionStatus(
                inputContext,
                out uint conversionMode,
                out uint sentenceMode);
            return new InputMethodSnapshot(
                keyboardLayout,
                true,
                hasConversionState,
                imeOpen,
                conversionMode,
                sentenceMode);
        }
        finally
        {
            ImmReleaseContext(foregroundWindow, inputContext);
        }
    }

    public void Restore(nint targetWindow)
    {
        if (_keyboardLayout != 0 && GetKeyboardLayout(0) != _keyboardLayout)
            ActivateKeyboardLayout(_keyboardLayout, 0);

        if (!_hasImeState || targetWindow == 0) return;

        nint inputContext = ImmGetContext(targetWindow);
        if (inputContext == 0) return;

        try
        {
            if (ImmGetOpenStatus(inputContext) != _imeOpen)
                ImmSetOpenStatus(inputContext, _imeOpen);

            if (_hasConversionState &&
                ImmGetConversionStatus(inputContext, out uint conversionMode, out uint sentenceMode) &&
                (conversionMode != _conversionMode || sentenceMode != _sentenceMode))
            {
                ImmSetConversionStatus(inputContext, _conversionMode, _sentenceMode);
            }
        }
        finally
        {
            ImmReleaseContext(targetWindow, inputContext);
        }
    }

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint windowHandle, out uint processId);

    [DllImport("user32.dll")]
    private static extern nint GetKeyboardLayout(uint threadId);

    [DllImport("user32.dll")]
    private static extern nint ActivateKeyboardLayout(nint keyboardLayout, uint flags);

    [DllImport("imm32.dll")]
    private static extern nint ImmGetContext(nint windowHandle);

    [DllImport("imm32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ImmReleaseContext(nint windowHandle, nint inputContext);

    [DllImport("imm32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ImmGetOpenStatus(nint inputContext);

    [DllImport("imm32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ImmSetOpenStatus(nint inputContext, [MarshalAs(UnmanagedType.Bool)] bool open);

    [DllImport("imm32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ImmGetConversionStatus(nint inputContext, out uint conversionMode, out uint sentenceMode);

    [DllImport("imm32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ImmSetConversionStatus(nint inputContext, uint conversionMode, uint sentenceMode);
}
