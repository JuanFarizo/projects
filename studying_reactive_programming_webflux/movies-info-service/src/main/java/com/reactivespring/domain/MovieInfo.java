package com.reactivespring.domain;

import java.time.LocalDate;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document
public class MovieInfo {

    @Id
    private String movieInfoId;
    @NotBlank(message = "The name must be present")
    private String name;
    @NotNull
    @Positive(message = "Year must be positive number")
    private Integer year;
    private List<@NotBlank(message = "Movie cast must not be empty") String> cast;
    private LocalDate release_date;
}
