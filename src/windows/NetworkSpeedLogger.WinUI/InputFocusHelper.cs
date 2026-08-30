using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;

namespace NetworkSpeedLogger;

internal static class InputFocusHelper
{
    public static bool ShouldClearFocus(XamlRoot xamlRoot, DependencyObject? pointerSource)
    {
        DependencyObject? focused = FocusManager.GetFocusedElement(xamlRoot) as DependencyObject;
        return IsWithinInput(focused) && !IsWithinInteractiveControl(pointerSource);
    }

    private static bool IsWithinInput(DependencyObject? element)
    {
        while (element is not null)
        {
            if (element is TextBox or NumberBox or ComboBox) return true;
            element = VisualTreeHelper.GetParent(element);
        }
        return false;
    }

    private static bool IsWithinInteractiveControl(DependencyObject? element)
    {
        while (element is not null)
        {
            if (element is TextBox or NumberBox or ComboBox or ButtonBase or SelectorItem) return true;
            element = VisualTreeHelper.GetParent(element);
        }
        return false;
    }
}
