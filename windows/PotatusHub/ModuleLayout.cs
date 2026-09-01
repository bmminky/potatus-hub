using System.Windows;

namespace PotatusHub;

public enum ModuleAxis
{
    Horizontal,
    Vertical,
}

public enum MergeDirection
{
    Left,
    Right,
    Above,
    Below,
}

public sealed class LayoutCell
{
    public MetricKind Kind { get; set; }
    public int Column { get; set; }
    public int Row { get; set; }

    public LayoutCell Clone() => new() { Kind = Kind, Column = Column, Row = Row };
}

public sealed class ModuleLayout
{
    public const double CellWidth = 160;
    public const double NormalCellHeight = 96;
    public const double ThreeVerticalCellHeight = 70;

    public List<LayoutCell> Cells { get; }

    public ModuleLayout(IEnumerable<LayoutCell> cells)
    {
        Cells = cells.Select(cell => cell.Clone()).ToList();
        Normalize();
    }

    public static ModuleLayout Linear(IEnumerable<MetricKind> kinds, ModuleAxis axis)
    {
        var cells = kinds.Select((kind, index) => new LayoutCell
        {
            Kind = kind,
            Column = axis == ModuleAxis.Horizontal ? index : 0,
            Row = axis == ModuleAxis.Vertical ? index : 0,
        });
        return new ModuleLayout(cells);
    }

    public int ColumnCount => Cells.Count == 0 ? 0 : Cells.Max(cell => cell.Column) + 1;
    public int RowCount => Cells.Count == 0 ? 0 : Cells.Max(cell => cell.Row) + 1;
    public double CellHeight => Cells.Count == 3 && ColumnCount == 1 && RowCount == 3
        ? ThreeVerticalCellHeight
        : NormalCellHeight;
    public Size Size => new(CellWidth * ColumnCount, CellHeight * RowCount);
    public ModuleAxis PrimaryAxis => ColumnCount >= RowCount ? ModuleAxis.Horizontal : ModuleAxis.Vertical;
    public IReadOnlyList<MetricKind> Kinds => Cells
        .OrderBy(cell => cell.Row)
        .ThenBy(cell => cell.Column)
        .Select(cell => cell.Kind)
        .ToList();

    public LayoutCell? Cell(MetricKind kind) => Cells.FirstOrDefault(cell => cell.Kind == kind);

    public ModuleLayout Removing(MetricKind kind)
    {
        var remaining = Cells.Where(cell => cell.Kind != kind).Select(cell => cell.Clone()).ToList();
        if (remaining.Count > 1)
        {
            // Removing the corner of an L-shaped group can leave the two
            // survivors diagonal to each other. A diagonal 2-cell layout
            // still renders as a single window (with an empty, transparent
            // gap cell between them), which looks like two separate cards
            // but drags as one. Force survivors back onto a single row or
            // column so a real gap only ever comes from truly separate windows.
            var sameRow = remaining.Select(cell => cell.Row).Distinct().Count() == 1;
            var sameColumn = remaining.Select(cell => cell.Column).Distinct().Count() == 1;
            if (sameRow)
            {
                var ordered = remaining.OrderBy(cell => cell.Column).ToList();
                for (var i = 0; i < ordered.Count; i++) ordered[i].Column = i;
            }
            else if (sameColumn)
            {
                var ordered = remaining.OrderBy(cell => cell.Row).ToList();
                for (var i = 0; i < ordered.Count; i++) ordered[i].Row = i;
            }
            else
            {
                var ordered = remaining.OrderBy(cell => cell.Row).ThenBy(cell => cell.Column).ToList();
                for (var i = 0; i < ordered.Count; i++)
                {
                    ordered[i].Column = i;
                    ordered[i].Row = 0;
                }
            }
        }
        var result = new ModuleLayout(remaining);
        result.Normalize();
        return result;
    }

    public static ModuleLayout Merged(
        ModuleLayout moving,
        ModuleLayout other,
        MergeDirection side,
        MetricKind? target)
    {
        if (moving.Cells.Count == 1 && target is { } targetKind && other.Cell(targetKind) is { } targetCell)
        {
            var movingCell = moving.Cells[0].Clone();
            if ((side == MergeDirection.Left || side == MergeDirection.Right) && other.ColumnCount == 1)
            {
                movingCell.Column = side == MergeDirection.Left ? -1 : 1;
                movingCell.Row = targetCell.Row;
                return new ModuleLayout(other.Cells.Append(movingCell));
            }
            if ((side == MergeDirection.Above || side == MergeDirection.Below) && other.RowCount == 1)
            {
                movingCell.Column = targetCell.Column;
                movingCell.Row = side == MergeDirection.Above ? -1 : 1;
                return new ModuleLayout(other.Cells.Append(movingCell));
            }
        }

        var left = moving.Cells.Select(cell => cell.Clone()).ToList();
        var right = other.Cells.Select(cell => cell.Clone()).ToList();
        switch (side)
        {
            case MergeDirection.Left:
                foreach (var cell in right) cell.Column += moving.ColumnCount;
                break;
            case MergeDirection.Right:
                foreach (var cell in left) cell.Column += other.ColumnCount;
                break;
            case MergeDirection.Above:
                foreach (var cell in right) cell.Row += moving.RowCount;
                break;
            case MergeDirection.Below:
                foreach (var cell in left) cell.Row += other.RowCount;
                break;
        }
        return new ModuleLayout(left.Concat(right));
    }

    public MetricKind? NearestKind(Point pointInCard)
    {
        return Cells
            .OrderBy(cell => Math.Pow((cell.Column + 0.5) * CellWidth - pointInCard.X, 2)
                + Math.Pow((cell.Row + 0.5) * CellHeight - pointInCard.Y, 2))
            .Select(cell => (MetricKind?)cell.Kind)
            .FirstOrDefault();
    }

    private void Normalize()
    {
        if (Cells.Count == 0) return;
        var minColumn = Cells.Min(cell => cell.Column);
        var minRow = Cells.Min(cell => cell.Row);
        foreach (var cell in Cells)
        {
            cell.Column -= minColumn;
            cell.Row -= minRow;
        }
    }
}
