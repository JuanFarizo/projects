package studying_reactive_programming_webflux.service;

import java.time.Duration;
import java.util.List;
import java.util.function.Function;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public class FluxAndMonoGenerateService {

    public Flux<String> namesFlux() {
        return Flux.fromIterable(List.of("Alex", "Ben", "Pepe"));
    }

    public Mono<String> nameMono() {
        return Mono.just("Pepe trueno");
    }

    public Flux<String> namesFlux_flatMap() {
        return Flux.fromIterable(List.of("Alex", "Ben", "Pepe"))
                .map(String::toUpperCase)
                .flatMap(s -> splitString(s))
                .log();
    }

    public Flux<String> namesFlux_flatMap_async() {
        return Flux.fromIterable(List.of("Alex", "Ben", "Pepe"))
                .map(String::toUpperCase)
                .flatMap(s -> splitString_withDelay(s))
                .log();
    }

    public Flux<String> namesFlux_transform() {
        Function<Flux<String>, Flux<String>> transformOperation = flux -> flux.map(String::toUpperCase);
        return Flux.fromIterable(List.of("Alex", "Ben", "Pepe"))
                .transform(transformOperation)
                .log();
    }

    public Flux<String> namesFlux_flatMapMany() {
        return Mono.just("alex")
                .map(String::toUpperCase)
                .flatMapMany(this::splitString) // flatMapMany only work if the function call returns a Flux
                .log();
    }

    public Flux<String> namesFlux_concatMap_async() { // Concat map preserves order
        return Flux.fromIterable(List.of("Alex", "Ben", "Pepe"))
                .map(String::toUpperCase)
                .concatMap(s -> splitString_withDelay(s))
                .log();
    }

    public Flux<String> splitString_withDelay(String name) {
        String[] charArr = name.split("");
        Duration delayDuration = java.time.Duration.ofMillis(1500l);
        return Flux.fromArray(charArr).delayElements(delayDuration);
    }

    public Mono<List<String>> nameMono_flatMap() {
        return Mono.just("alex")
                .map(String::toUpperCase)
                .flatMap(s -> splitStringMono(s));
    }

    public Mono<List<String>> splitStringMono(String s) {
        String[] charArr = s.split("");
        List<String> charList = List.of(charArr);
        return Mono.just(charList);
    }

    public Flux<String> splitString(String name) {
        String[] charArr = name.split("");
        return Flux.fromArray(charArr);
    }

    public static void main(String[] args) throws InterruptedException {
        FluxAndMonoGenerateService service = new FluxAndMonoGenerateService();
        // service.namesFlux().subscribe(System.out::println);

        // service.nameMono().subscribe(System.out::println);
        service.namesFlux_transform().subscribe(System.out::println);
    }
}
