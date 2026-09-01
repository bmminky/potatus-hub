using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace PotatusHub;

public partial class ModulePanel : Window
{
    public const double ShadowPadding = 16;
    private readonly SystemMonitor _monitor;
    private readonly Dictionary<MetricKind, MetricVisual> _visuals = [];
    private bool _allowClose;
    private DispatcherTimer? _holdTimer;
    private Border? _pressedTile;
    private Point _pressPoint;

    private sealed record MetricVisual(TextBlock Value, Border Track, Border Fill);

    public ModuleLayout Layout { get; private set; }
    public event Action<ModulePanel>? DragCompleted;
    public event Action? RightClicked;
    public event Action<ModulePanel>? DoubleClicked;
    public event Func<ModulePanel, MetricKind, ModulePanel?>? ExtractionRequested;

    public Rect CardBounds => new(
        Left + ShadowPadding,
        Top + ShadowPadding,
        Layout.Size.Width,
        Layout.Size.Height);

    public ModulePanel(SystemMonitor monitor, ModuleLayout layout)
    {
        InitializeComponent();
        _monitor = monitor;
        Layout = layout;
        Topmost = AppSettings.Current.AlwaysOnTop;
        _monitor.PropertyChanged += OnMonitorChanged;
        MouseRightButtonUp += (_, e) =>
        {
            e.Handled = true;
            RightClicked?.Invoke();
        };
        PreviewMouseMove += OnPreviewMouseMove;
        PreviewMouseLeftButtonUp += (_, _) => CancelHold();
        Closing += (_, e) =>
        {
            if (_allowClose) return;
            e.Cancel = true;
            HideAnimated();
        };
        BuildSurface(keepCenter: false);
    }

    public void SetLayout(ModuleLayout layout, bool animated = true)
    {
        var oldLeft = Left;
        var oldTop = Top;
        var oldWidth = Width;
        var oldHeight = Height;
        var center = new Point(oldLeft + oldWidth / 2, oldTop + oldHeight / 2);
        Layout = layout;
        BuildSurface(keepCenter: false);
        var targetWidth = Width;
        var targetHeight = Height;
        var targetLeft = center.X - targetWidth / 2;
        var targetTop = center.Y - targetHeight / 2;
        if (!animated)
        {
            Left = targetLeft;
            Top = targetTop;
            return;
        }

        Left = oldLeft;
        Top = oldTop;
        Width = oldWidth;
        Height = oldHeight;
        var ease = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.35 };
        var duration = TimeSpan.FromMilliseconds(340);
        AnimateWindowProperty(LeftProperty, targetLeft, ease, duration);
        AnimateWindowProperty(TopProperty, targetTop, ease, duration);
        AnimateWindowProperty(WidthProperty, targetWidth, ease, duration);
        AnimateWindowProperty(HeightProperty, targetHeight, ease, duration);
    }

    public void ClosePermanently()
    {
        CancelHold();
        _allowClose = true;
        _monitor.PropertyChanged -= OnMonitorChanged;
        Close();
    }

    public void ShowAnimated()
    {
        if (IsVisible) return;
        Opacity = 0;
        Surface.RenderTransform = new ScaleTransform(0.92, 0.92);
        Show();
        AnimatePresentation(1, 1, hideAfter: false);
    }

    public void HideAnimated()
    {
        if (!IsVisible) return;
        AnimatePresentation(0, 0.94, hideAfter: true);
    }

    public MetricKind? KindNearest(Point screenPoint)
    {
        var local = new Point(screenPoint.X - CardBounds.Left, screenPoint.Y - CardBounds.Top);
        return Layout.NearestKind(local);
    }

    public void BeginExternalDrag()
    {
        Activate();
        try
        {
            DragMove();
            DragCompleted?.Invoke(this);
        }
        catch (InvalidOperationException)
        {
        }
    }

    private void BuildSurface(bool keepCenter)
    {
        var oldCenter = new Point(Left + Width / 2, Top + Height / 2);
        _visuals.Clear();
        Surface.Children.Clear();
        Surface.ColumnDefinitions.Clear();
        Surface.RowDefinitions.Clear();

        for (var column = 0; column < Layout.ColumnCount; column++)
            Surface.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(ModuleLayout.CellWidth) });
        for (var row = 0; row < Layout.RowCount; row++)
            Surface.RowDefinitions.Add(new RowDefinition { Height = new GridLength(Layout.CellHeight) });

        foreach (var cell in Layout.Cells)
        {
            var tile = BuildCell(cell.Kind, cell.Column, cell.Row);
            Grid.SetColumn(tile, cell.Column);
            Grid.SetRow(tile, cell.Row);
            Surface.Children.Add(tile);
        }

        var targetWidth = Layout.Size.Width + ShadowPadding * 2;
        var targetHeight = Layout.Size.Height + ShadowPadding * 2;
        Width = targetWidth;
        Height = targetHeight;
        Surface.Width = Layout.Size.Width;
        Surface.Height = Layout.Size.Height;
        if (keepCenter && !double.IsNaN(oldCenter.X))
        {
            Left = oldCenter.X - targetWidth / 2;
            Top = oldCenter.Y - targetHeight / 2;
        }
        UpdateValues();
    }

    private Border BuildCell(MetricKind kind, int column, int row)
    {
        bool Has(int c, int r) => Layout.Cells.Any(cell => cell.Column == c && cell.Row == r);
        var top = !Has(column, row - 1);
        var bottom = !Has(column, row + 1);
        var left = !Has(column - 1, row);
        var right = !Has(column + 1, row);
        const double radius = 14;

        var tile = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x1E, 0x1E, 0x20)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x3D, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(
                left ? 0.75 : 0,
                top ? 0.75 : 0,
                right ? 0.75 : 0.5,
                bottom ? 0.75 : 0.5),
            CornerRadius = new CornerRadius(
                top && left ? radius : 0,
                top && right ? radius : 0,
                bottom && right ? radius : 0,
                bottom && left ? radius : 0),
            Child = BuildCellContent(kind),
            Tag = kind,
        };
        tile.PreviewMouseLeftButtonDown += OnTileLeftButtonDown;
        return tile;
    }

    private UIElement BuildCellContent(MetricKind kind)
    {
        var accent = new SolidColorBrush(kind.Accent());
        var content = new Grid { Margin = new Thickness(16, 11, 16, 11) };
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });

        var heading = new Grid();
        var left = new StackPanel { Orientation = Orientation.Horizontal };
        left.Children.Add(new TextBlock
        {
            Text = kind.Glyph(),
            Foreground = accent,
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        });
        left.Children.Add(new TextBlock
        {
            Text = kind.Title(),
            Foreground = Brushes.White,
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(5, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        });
        heading.Children.Add(left);

        var value = new TextBlock
        {
            Text = "—",
            Foreground = accent,
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        heading.Children.Add(value);
        Grid.SetRow(heading, 0);
        content.Children.Add(heading);

        var track = new Border
        {
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(Color.FromArgb(0x33, 0x99, 0x99, 0x99)),
            VerticalAlignment = VerticalAlignment.Bottom,
        };
        var barGrid = new Grid();
        var fill = new Border
        {
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = accent,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        barGrid.Children.Add(fill);
        track.Child = barGrid;
        Grid.SetRow(track, 2);
        content.Children.Add(track);

        track.SizeChanged += (_, _) => UpdateVisual(kind);
        _visuals[kind] = new MetricVisual(value, track, fill);
        return content;
    }

    private void OnTileLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        e.Handled = true;
        if (e.ClickCount == 2 && Layout.Cells.Count > 1)
        {
            DoubleClicked?.Invoke(this);
            return;
        }

        if (Layout.Cells.Count > 1 && sender is Border tile)
        {
            _pressedTile = tile;
            _pressPoint = e.GetPosition(this);
            tile.CaptureMouse();
            _holdTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(380) };
            _holdTimer.Tick += (_, _) => ExtractHeldTile();
            _holdTimer.Start();
            return;
        }

        BeginExternalDrag();
    }

    private void OnPreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (_holdTimer is null || e.LeftButton != MouseButtonState.Pressed) return;
        var current = e.GetPosition(this);
        if (Math.Abs(current.X - _pressPoint.X) <= 6 && Math.Abs(current.Y - _pressPoint.Y) <= 6) return;
        CancelHold();
        BeginExternalDrag();
    }

    private void ExtractHeldTile()
    {
        var tile = _pressedTile;
        CancelHold();
        if (tile?.Tag is not MetricKind kind) return;
        var extracted = ExtractionRequested?.Invoke(this, kind);
        extracted?.BeginExternalDrag();
    }

    private void CancelHold()
    {
        _holdTimer?.Stop();
        _holdTimer = null;
        _pressedTile = null;
        if (Mouse.Captured is not null) Mouse.Capture(null);
    }

    private void OnMonitorChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) =>
        Dispatcher.Invoke(UpdateValues);

    private void UpdateValues()
    {
        foreach (var kind in _visuals.Keys.ToList()) UpdateVisual(kind);
    }

    private void UpdateVisual(MetricKind kind)
    {
        if (!_visuals.TryGetValue(kind, out var visual)) return;
        var value = _monitor.Value(kind);
        visual.Value.Text = value is { } number ? $"{Math.Round(number):0}%" : "—";
        visual.Value.Opacity = value is null ? 0.62 : 1;
        visual.Fill.Width = visual.Track.ActualWidth * Math.Clamp((value ?? 0) / 100, 0, 1);
    }

    private void AnimatePresentation(double opacity, double scale, bool hideAfter)
    {
        var ease = new CubicEase { EasingMode = EasingMode.EaseInOut };
        var duration = TimeSpan.FromMilliseconds(190);
        var opacityAnimation = new DoubleAnimation(opacity, duration) { EasingFunction = ease };
        if (hideAfter) opacityAnimation.Completed += (_, _) => Hide();
        BeginAnimation(OpacityProperty, opacityAnimation);

        var transform = Surface.RenderTransform as ScaleTransform ?? new ScaleTransform(1, 1);
        Surface.RenderTransform = transform;
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale, duration) { EasingFunction = ease });
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale, duration) { EasingFunction = ease });
    }

    private void AnimateWindowProperty(
        DependencyProperty property,
        double target,
        IEasingFunction ease,
        TimeSpan duration)
    {
        var animation = new DoubleAnimation(target, duration)
        {
            EasingFunction = ease,
            FillBehavior = FillBehavior.Stop,
        };
        animation.Completed += (_, _) =>
        {
            BeginAnimation(property, null);
            SetValue(property, target);
        };
        BeginAnimation(property, animation);
    }
}
