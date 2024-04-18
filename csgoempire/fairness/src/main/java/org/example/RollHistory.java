package org.example;

import java.io.Serializable;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class RollHistory implements Serializable {
    private boolean success;
    private Data data;

    public boolean isSuccess() {
        return success;
    }

    public void setSuccess(boolean success) {
        this.success = success;
    }

    public Data getData() {
        return data;
    }

    public void setData(Data data) {
        this.data = data;
    }

    public RollHistory() {
    }

    class Data {
        private LocalDate date;
        private List<Roll> rolls = new ArrayList<>();

        public Data() {
        }

        public LocalDate getDate() {
            return date;
        }

        public void setDate(LocalDate date) {
            this.date = date;
        }

        public List<Roll> getRolls() {
            return rolls;
        }

        public void setRolls(List<Roll> rolls) {
            this.rolls = rolls;
        }

    }
}
