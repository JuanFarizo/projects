package restricted.classes.instantiation.game.internal;

class BoardPrinter {
    private final BoardDimensions dimensions;

    public BoardPrinter(BoardDimensions dimensions) {
        this.dimensions = dimensions;
    }

    public void print(Board board) {
        printHorizontalBorder();

        printBoard(board);

        printHorizontalBorder();
    }

    private void printHorizontalBorder() {
        for (int c = 0; c < dimensions.getNumberOfColumns() * 4 + 1; c++) {
            System.out.print("-");
        }
        System.out.println();
    }

    private void printBoard(Board board) {
        for (int c = 0; c < dimensions.getNumberOfColumns(); c++) {
            System.out.print("|");
            for (int r = 0; r < dimensions.getNumberOfRows(); r++) {
                System.out.print(String.format(" %s |", board.getPrintableCellSign(r, c)));
            }
            System.out.println();
        }
    }

}
