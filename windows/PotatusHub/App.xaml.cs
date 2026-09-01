using System.Drawing;
using System.Windows;
using System.Windows.Forms;
using Application = System.Windows.Application;
using MessageBox = System.Windows.MessageBox;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;

namespace PotatusHub;

public partial class App : Application
{
    private readonly List<ModulePanel> _panels = [];
    private SystemMonitor _monitor = null!;
    private NotifyIcon _tray = null!;
    private Icon? _trayIcon;
    private ContextMenuStrip? _openMenu;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _monitor = new SystemMonitor();
        RestorePanels();

        _trayIcon = Environment.ProcessPath is { } path
            ? Icon.ExtractAssociatedIcon(path)
            : (Icon)SystemIcons.Application.Clone();
        _tray = new NotifyIcon
        {
            Visible = true,
            Text = "potatus hub",
            Icon = _trayIcon,
        };
        _tray.MouseClick += OnTrayClick;
        _monitor.Start();
    }

    private void RestorePanels()
    {
        var visible = AppSettings.Current.VisibleMetrics;
        var restored = new HashSet<MetricKind>();
        foreach (var saved in AppSettings.Current.Panels)
        {
            var cells = saved.Cells
                .Where(cell => visible.Contains(cell.Kind) && restored.Add(cell.Kind))
                .ToList();
            if (cells.Count == 0) continue;
            CreatePanel(new ModuleLayout(cells), saved.Left, saved.Top, animate: false);
        }

        var missing = Enum.GetValues<MetricKind>().Where(kind => visible.Contains(kind) && !restored.Contains(kind)).ToList();
        if (_panels.Count == 0 && missing.Count > 0)
        {
            var area = SystemParameters.WorkArea;
            var layout = ModuleLayout.Linear(missing, ModuleAxis.Vertical);
            CreatePanel(layout, area.Right - layout.Size.Width - ModulePanel.ShadowPadding * 2 - 16, area.Top + 16, animate: false);
        }
        else
        {
            var area = SystemParameters.WorkArea;
            foreach (var kind in missing)
            {
                CreatePanel(ModuleLayout.Linear([kind], ModuleAxis.Horizontal), area.Right - 208, area.Top + 16 + _panels.Count * 24, animate: false);
            }
        }
    }

    private ModulePanel CreatePanel(ModuleLayout layout, double left, double top, bool animate = true)
    {
        var panel = new ModulePanel(_monitor, layout)
        {
            Left = left,
            Top = top,
        };
        panel.DragCompleted += HandleDragCompleted;
        panel.RightClicked += ShowContextMenu;
        panel.DoubleClicked += ToggleOrientation;
        panel.ExtractionRequested += ExtractMetric;
        _panels.Add(panel);
        if (animate) panel.ShowAnimated(); else panel.Show();
        return panel;
    }

    private void ClosePanel(ModulePanel panel)
    {
        _panels.Remove(panel);
        panel.ClosePermanently();
    }

    private ModulePanel? ExtractMetric(ModulePanel source, MetricKind kind)
    {
        if (source.Layout.Cells.Count < 2 || source.Layout.Cell(kind) is not { } cell) return null;
        var oldCard = source.CardBounds;
        var extractedLeft = oldCard.Left + cell.Column * ModuleLayout.CellWidth;
        var extractedTop = oldCard.Top + cell.Row * source.Layout.CellHeight;
        var remaining = source.Layout.Removing(kind);
        source.SetLayout(remaining, animated: false);
        source.Left = oldCard.Left - ModulePanel.ShadowPadding;
        source.Top = oldCard.Top - ModulePanel.ShadowPadding;

        var panel = CreatePanel(
            ModuleLayout.Linear([kind], ModuleAxis.Horizontal),
            extractedLeft - ModulePanel.ShadowPadding,
            extractedTop - ModulePanel.ShadowPadding,
            animate: false);
        SaveLayout();
        return panel;
    }

    private void OnTrayClick(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Right) ShowContextMenu();
        else TogglePresentation();
    }

    private void TogglePresentation()
    {
        if (_panels.Any(panel => panel.IsVisible))
        {
            SaveLayout();
            foreach (var panel in _panels) panel.HideAnimated();
        }
        else
        {
            foreach (var panel in _panels) panel.ShowAnimated();
        }
    }

    private void HandleDragCompleted(ModulePanel moving)
    {
        var source = moving.CardBounds;
        var candidate = _panels
            .Where(panel => panel != moving)
            .Select(panel => SnapCandidate(moving, panel))
            .Where(candidate => candidate is not null)
            .OrderBy(candidate => candidate!.Value.Score)
            .FirstOrDefault();

        if (candidate is { } snap)
        {
            Merge(moving, snap.Target, snap.Side, snap.TargetKind);
        }
        else
        {
            SaveLayout();
        }
    }

    private readonly record struct SnapInfo(
        ModulePanel Target,
        MergeDirection Side,
        MetricKind? TargetKind,
        double Score);

    private static SnapInfo? SnapCandidate(ModulePanel moving, ModulePanel target)
    {
        var source = moving.CardBounds;
        var destination = target.CardBounds;
        var capture = destination;
        capture.Inflate(38, 38);
        if (!capture.IntersectsWith(source)) return null;

        var sourceCenter = new Point(source.Left + source.Width / 2, source.Top + source.Height / 2);
        var targetCenter = new Point(destination.Left + destination.Width / 2, destination.Top + destination.Height / 2);
        var dx = sourceCenter.X - targetCenter.X;
        var dy = sourceCenter.Y - targetCenter.Y;
        var side = Math.Abs(dx) >= Math.Abs(dy)
            ? dx < 0 ? MergeDirection.Left : MergeDirection.Right
            : dy < 0 ? MergeDirection.Above : MergeDirection.Below;

        var overlapX = Math.Max(0, Math.Min(source.Right, destination.Right) - Math.Max(source.Left, destination.Left));
        var overlapY = Math.Max(0, Math.Min(source.Bottom, destination.Bottom) - Math.Max(source.Top, destination.Top));
        var perpendicularOverlap = side is MergeDirection.Left or MergeDirection.Right ? overlapY : overlapX;
        var requiredOverlap = side is MergeDirection.Left or MergeDirection.Right ? 22 : 30;
        if (!source.IntersectsWith(destination) && perpendicularOverlap < requiredOverlap) return null;

        var targetKind = target.KindNearest(sourceCenter);
        return new SnapInfo(target, side, targetKind, Math.Sqrt(dx * dx + dy * dy));
    }

    private void Merge(ModulePanel moving, ModulePanel target, MergeDirection side, MetricKind? targetKind)
    {
        var union = Rect.Union(moving.CardBounds, target.CardBounds);
        var layout = ModuleLayout.Merged(moving.Layout, target.Layout, side, targetKind);
        ClosePanel(moving);
        // Reuse target's existing (already on-screen) window instead of
        // closing it too and creating a brand new one: a freshly created
        // layered window takes a beat before DWM actually composites its
        // first frame, which showed up as a brief blank flash on merge.
        target.SetLayout(layout, animated: false);
        target.Left = union.Left + (union.Width - layout.Size.Width) / 2 - ModulePanel.ShadowPadding;
        target.Top = union.Top + (union.Height - layout.Size.Height) / 2 - ModulePanel.ShadowPadding;
        SaveLayout();
    }

    private void ToggleOrientation(ModulePanel panel)
    {
        if (panel.Layout.Cells.Count < 2) return;
        var center = new Point(panel.CardBounds.Left + panel.CardBounds.Width / 2, panel.CardBounds.Top + panel.CardBounds.Height / 2);
        var next = panel.Layout.PrimaryAxis == ModuleAxis.Horizontal ? ModuleAxis.Vertical : ModuleAxis.Horizontal;
        var layout = ModuleLayout.Linear(panel.Layout.Kinds, next);
        panel.SetLayout(layout);
        panel.Left = center.X - layout.Size.Width / 2 - ModulePanel.ShadowPadding;
        panel.Top = center.Y - layout.Size.Height / 2 - ModulePanel.ShadowPadding;
        SaveLayout();
    }

    private void Arrange(ModuleAxis axis)
    {
        var kinds = AppSettings.Current.VisibleMetrics.OrderBy(kind => kind).ToList();
        if (kinds.Count == 0) return;
        var center = CurrentCenter();
        var layout = ModuleLayout.Linear(kinds, axis);
        var left = center.X - layout.Size.Width / 2 - ModulePanel.ShadowPadding;
        var top = center.Y - layout.Size.Height / 2 - ModulePanel.ShadowPadding;

        // Reuse one existing window (if any) instead of closing every panel
        // and creating a brand new one, which flashes blank for a beat while
        // the new layered window's first frame gets composited.
        var survivor = _panels.FirstOrDefault();
        foreach (var panel in _panels.Where(candidate => candidate != survivor).ToList()) ClosePanel(panel);
        if (survivor is null)
        {
            CreatePanel(layout, left, top, animate: false);
        }
        else
        {
            survivor.SetLayout(layout, animated: false);
            survivor.Left = left;
            survivor.Top = top;
        }
        SaveLayout();
    }

    private void DetachAll()
    {
        var kinds = AppSettings.Current.VisibleMetrics.OrderBy(kind => kind).ToList();
        if (kinds.Count == 0) return;
        var center = CurrentCenter();
        foreach (var panel in _panels.ToList()) ClosePanel(panel);
        const double gap = 24;
        var total = kinds.Count * ModuleLayout.CellWidth + (kinds.Count - 1) * gap;
        var cardLeft = center.X - total / 2;
        foreach (var (kind, index) in kinds.Select((kind, index) => (kind, index)))
        {
            CreatePanel(
                ModuleLayout.Linear([kind], ModuleAxis.Horizontal),
                cardLeft + index * (ModuleLayout.CellWidth + gap) - ModulePanel.ShadowPadding,
                center.Y - ModuleLayout.NormalCellHeight / 2 - ModulePanel.ShadowPadding,
                animate: false);
        }
        SaveLayout();
    }

    private Point CurrentCenter()
    {
        if (_panels.Count == 0)
        {
            var area = SystemParameters.WorkArea;
            return new Point(area.Right - 220, area.Top + 140);
        }
        var union = _panels.Select(panel => panel.CardBounds).Aggregate((left, right) => Rect.Union(left, right));
        return new Point(union.Left + union.Width / 2, union.Top + union.Height / 2);
    }

    private void ToggleMetric(MetricKind kind)
    {
        var visible = AppSettings.Current.VisibleMetrics;
        if (visible.Remove(kind))
        {
            var panel = _panels.FirstOrDefault(candidate => candidate.Layout.Kinds.Contains(kind));
            if (panel is not null)
            {
                var next = panel.Layout.Removing(kind);
                if (next.Cells.Count == 0) ClosePanel(panel); else panel.SetLayout(next);
            }
        }
        else
        {
            visible.Add(kind);
            var area = SystemParameters.WorkArea;
            CreatePanel(ModuleLayout.Linear([kind], ModuleAxis.Horizontal), area.Right - 208, area.Top + 16);
        }
        AppSettings.Save();
        SaveLayout();
    }

    private void ShowContextMenu()
    {
        _openMenu?.Dispose();
        var menu = new ContextMenuStrip();
        _openMenu = menu;

        var modules = new ToolStripMenuItem(L.T("모듈", "Modules", "モジュール", "模块"));
        foreach (var kind in Enum.GetValues<MetricKind>())
        {
            var captured = kind;
            modules.DropDownItems.Add(new ToolStripMenuItem(kind.Title(), null, (_, _) => ToggleMetric(captured))
            {
                Checked = AppSettings.Current.VisibleMetrics.Contains(kind),
            });
        }
        menu.Items.Add(modules);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L.T("새로고침", "Refresh", "更新", "刷新"), null, (_, _) => _monitor.Refresh());
        menu.Items.Add(L.T("숨기기", "Hide", "隠す", "隐藏"), null, (_, _) =>
        {
            SaveLayout();
            foreach (var panel in _panels) panel.HideAnimated();
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L.T("세로 정렬", "Arrange Vertically", "縦に整列", "纵向排列"), null, (_, _) => Arrange(ModuleAxis.Vertical));
        menu.Items.Add(L.T("가로 정렬", "Arrange Horizontally", "横に整列", "横向排列"), null, (_, _) => Arrange(ModuleAxis.Horizontal));
        menu.Items.Add(L.T("분리", "Detach", "分離", "分离"), null, (_, _) => DetachAll());

        var onTop = new ToolStripMenuItem(L.T("항상 위", "Always on Top", "常に手前に表示", "总在最前"), null, (_, _) =>
        {
            AppSettings.Current.AlwaysOnTop = !AppSettings.Current.AlwaysOnTop;
            foreach (var panel in _panels) panel.Topmost = AppSettings.Current.AlwaysOnTop;
            AppSettings.Save();
        }) { Checked = AppSettings.Current.AlwaysOnTop };
        menu.Items.Add(onTop);

        menu.Items.Add(new ToolStripMenuItem(L.T("로그인 시 자동 실행", "Launch at Login", "ログイン時に起動", "开机自启动"), null, (_, _) => LaunchAtLogin.Toggle())
        {
            Checked = LaunchAtLogin.IsEnabled,
        });
        menu.Items.Add(BuildLanguageMenu());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(L.T("potatus hub 정보", "About potatus hub", "potatus hub について", "关于 potatus hub"), null, (_, _) => Dispatcher.BeginInvoke(ShowAbout));
        menu.Items.Add(L.T("앱 종료하기", "Quit", "アプリを終了", "退出应用"), null, (_, _) => Quit());
        menu.Closed += (_, _) =>
        {
            if (ReferenceEquals(_openMenu, menu)) _openMenu = null;
            // Closed fires from inside the dropdown's own SetVisibleCore/hide
            // sequence, so disposing `menu` here reenters and crashes that
            // still-running framework code with ObjectDisposedException.
            // Defer the dispose to a fresh message so the current one finishes first.
            var deferred = new System.Windows.Forms.Timer { Interval = 1 };
            deferred.Tick += (_, _) =>
            {
                deferred.Stop();
                deferred.Dispose();
                menu.Dispose();
            };
            deferred.Start();
        };
        menu.Show(System.Windows.Forms.Cursor.Position);
    }

    private static ToolStripMenuItem BuildLanguageMenu()
    {
        var parent = new ToolStripMenuItem("언어 / Language / 言語 / 语言");
        (L.Language Language, string Title)[] options =
        [
            (L.Language.System, L.T("시스템 언어 따름", "Follow System", "システム言語に従う", "跟随系统语言")),
            (L.Language.Korean, "한국어"),
            (L.Language.English, "English"),
            (L.Language.Japanese, "日本語"),
            (L.Language.Chinese, "中文"),
        ];
        foreach (var option in options)
        {
            var captured = option.Language;
            parent.DropDownItems.Add(new ToolStripMenuItem(option.Title, null, (_, _) => L.Preference = captured)
            {
                Checked = L.Preference == option.Language,
            });
        }
        return parent;
    }

    private static void ShowAbout()
    {
        var version = System.Reflection.Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0.4.1";
        MessageBox.Show(
            L.T(
                $"potatus hub {version}\nWindows 11용 로컬 시스템 모니터\n만든 사람  bmminky\nhttps://github.com/bmminky/potatus-hub",
                $"potatus hub {version}\nLocal system monitor for Windows 11\nCreated by bmminky\nhttps://github.com/bmminky/potatus-hub",
                $"potatus hub {version}\nWindows 11向けローカルシステムモニター\n作成者 bmminky\nhttps://github.com/bmminky/potatus-hub",
                $"potatus hub {version}\n适用于 Windows 11 的本地系统监视器\n作者 bmminky\nhttps://github.com/bmminky/potatus-hub"),
            "potatus hub",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void SaveLayout()
    {
        AppSettings.Current.Panels = _panels.Select(panel => new SavedPanel
        {
            Cells = panel.Layout.Cells.Select(cell => cell.Clone()).ToList(),
            Left = panel.Left,
            Top = panel.Top,
        }).ToList();
        AppSettings.Save();
    }

    private void Quit()
    {
        SaveLayout();
        _monitor.Dispose();
        foreach (var panel in _panels.ToList()) ClosePanel(panel);
        _tray.Visible = false;
        _tray.Dispose();
        _trayIcon?.Dispose();
        Shutdown();
    }
}
