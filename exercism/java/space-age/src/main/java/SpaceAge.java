class SpaceAge {
    private static final int SEC_YEAR_ON_EARTH          = 31_557_600;
    private static final double SEC_YEAR_ON_MERCURY   = 0.2408467 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_VENUS     = 0.61519726 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_MARS      = 1.8808158 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_JUPITER   = 11.862615 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_SATURN    = 29.447498 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_URANUS    = 84.016846 * SEC_YEAR_ON_EARTH;
    private static final double SEC_YEAR_ON_NEPTUNE   = 164.79132 * SEC_YEAR_ON_EARTH;
    private final double seconds;

    SpaceAge(double seconds) {
        this.seconds = seconds;
    }

    double getSeconds() {
        return this.seconds;
    }

    double onEarth() {
        return this.seconds / SEC_YEAR_ON_EARTH;
    }

    double onMercury() {
        return this.seconds / SEC_YEAR_ON_MERCURY;
    }

    double onVenus() {
        return this.seconds / SEC_YEAR_ON_VENUS;
    }

    double onMars() {
        return this.seconds / SEC_YEAR_ON_MARS;
    }

    double onJupiter() {
        return this.seconds / SEC_YEAR_ON_JUPITER;
    }

    double onSaturn() {
        return this.seconds / SEC_YEAR_ON_SATURN;
    }

    double onUranus() {
        return this.seconds / SEC_YEAR_ON_URANUS;
    }

    double onNeptune() {
        return this.seconds / SEC_YEAR_ON_NEPTUNE;
    }

}
