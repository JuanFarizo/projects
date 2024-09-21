package restricted.classes.instantiation.game.internal;

class Cell {
    private Sign sign;

    public Cell() {
        this.sign = Sign.EMPTY;
    }

    public boolean isEmpty() {
        return sign == Sign.EMPTY;
    }

    public Sign getSign() {
        return this.sign;
    }

    public void setSign(Sign sign) {
        this.sign = sign;
    }

}
