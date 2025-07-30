public class Lasagna {
    int expectedMinutesInOven = 40; // TODO: define the 'expectedMinutesInOven()' method
    public int expectedMinutesInOven() {
        return this.expectedMinutesInOven;
    }
    // TODO: define the 'remainingMinutesInOven()' method
    public int remainingMinutesInOven(int minutesInOven) {
        return this.expectedMinutesInOven - minutesInOven;
    }

    public int preparationTimeInMinutes(int layers) {
        return layers * 2;
    }

    public int totalTimeInMinutes(int layers, int cookingTime) {
        return this.preparationTimeInMinutes(layers) + cookingTime;
    }
    // TODO: define the 'preparationTimeInMinutes()' method
 
    // TODO: define the 'totalTimeInMinutes()' method
}
