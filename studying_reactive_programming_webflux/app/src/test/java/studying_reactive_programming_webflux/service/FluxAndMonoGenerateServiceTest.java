package studying_reactive_programming_webflux.service;

import java.util.List;

import org.junit.jupiter.api.Test;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

public class FluxAndMonoGenerateServiceTest {
    FluxAndMonoGenerateService service = new FluxAndMonoGenerateService();

    @Test
    void testFluxNames() {
        // given
        // when
        Flux<String> namesFlux = service.namesFlux();
        // then
        StepVerifier.create(namesFlux)
                .expectNext("Alex", "Ben", "Pepe")
                .verifyComplete();

        StepVerifier.create(namesFlux) // create function call basically takes care of invoking the subscribe call
                                       // which automatically triggers the publisher to send the events.
                .expectNext("Alex")
                .expectNextCount(2)
                .verifyComplete();
    }

    @Test
    void testFluxnames_flatMap() {
        Flux<String> namesFlux = service.namesFlux_flatMap();

        StepVerifier.create(namesFlux)
                .expectNext("A")
                .expectNext("L");
    }

    @Test
    void testFluxnames_flatMap_async() {
        Flux<String> namesFlux = service.namesFlux_flatMap();
        StepVerifier.create(namesFlux)
                .expectNextCount(11)
                .verifyComplete();
    }

    @Test
    void testFluxnames_flatMapMany() {
        Flux<String> namesFlux = service.namesFlux_flatMapMany();
        StepVerifier.create(namesFlux)
                .expectNext("A")
                .expectNext("L")
                .expectNext("E")
                .expectNext("X")
                .verifyComplete();
    }

    @Test
    void testexplore_concat() {
        Flux<String> namesFlux = service.explore_concat();
        StepVerifier.create(namesFlux)
                .expectNext("A", "B", "C", "D", "E", "F")
                .verifyComplete();
    }

    @Test
    void testexplore_concatwith() {
        Flux<String> namesFlux = service.explore_concatwith();
        StepVerifier.create(namesFlux)
                .expectNext("A", "B", "C", "D", "E", "F")
                .verifyComplete();
    }

    @Test
    void testmono_concatwith() {
        Flux<String> namesFlux = service.concat_with_mono();
        StepVerifier.create(namesFlux)
                .expectNext("A", "B")
                .verifyComplete();
    }

    @Test
    void testMonoName_flatMap() {
        Mono<List<String>> monoListString = service.nameMono_flatMap();
        StepVerifier.create(monoListString)
                .expectNext(List.of("A", "L", "E", "X"))
                .verifyComplete();
    }

    @Test
    void testFluxnames_concatMap_async() { // Concat map preserves order
        Flux<String> namesFlux = service.namesFlux_flatMap();
        StepVerifier.create(namesFlux)
                .expectNext("A")
                .expectNext("L")
                .expectNext("E")
                .expectNext("X");
    }
}
