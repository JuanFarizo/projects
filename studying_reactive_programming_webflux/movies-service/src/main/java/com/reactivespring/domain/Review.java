package com.reactivespring.domain;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class Review {

    private String reviewId;
    @NotNull(message = "rating.movieInfoId : must not be null")
    private Long movieInfoId;
    private String comment;
    @PositiveOrZero(message = "rating.negative : please pass a non-negative value")
    private Double rating;
}
