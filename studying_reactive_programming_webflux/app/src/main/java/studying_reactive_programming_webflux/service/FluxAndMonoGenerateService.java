package studying_reactive_programming_webflux.service;

import java.time.Duration;
import java.util.List;
import java.util.function.BiFunction;
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

    public Flux<String> explore_concat() {
        var abcFlux = Flux.just("A", "B", "C");
        var defFlux = Flux.just("D", "E", "F");
        return Flux.concat(abcFlux, defFlux).log();
    }

    public Flux<String> explore_concatwith() {
        var abcFlux = Flux.just("A", "B", "C");
        var defFlux = Flux.just("D", "E", "F");
        return abcFlux.concatWith(defFlux).log();
    }

    public Flux<String> concat_with_mono() {
        var aMono = Mono.just("A");
        var bMono = Mono.just("B");

        return aMono.concatWith(bMono);
    }

    public Flux<String> explore_merge() {
        var abcFlux = Flux.just("A", "B", "C")
                .delayElements(Duration.ofMillis(125));
        var defFlux = Flux.just("D", "E", "F")
                .delayElements(Duration.ofMillis(125));
        return Flux.merge(abcFlux, defFlux).log();
    }

    public Flux<String> explore_mergewith() {
        var abcFlux = Flux.just("A", "B", "C")
                .delayElements(Duration.ofMillis(125));
        var defFlux = Flux.just("D", "E", "F")
                .delayElements(Duration.ofMillis(125));
        return abcFlux.mergeWith(defFlux).log();
    }

    public Flux<String> explore_zip() {
        BiFunction<String, String, String> lambda = (first, second) -> first + second;
        var abcFlux = Flux.just("A", "B", "C")
                .delayElements(Duration.ofMillis(125));
        var defFlux = Flux.just("D", "E", "F")
                .delayElements(Duration.ofMillis(125));
        return Flux.zip(abcFlux, defFlux, lambda).log();
    }

    public Flux<String> explore_zipMap() {
        var abcFlux = Flux.just("A", "B", "C");
        var defFlux = Flux.just("D", "E", "F");
        var _123Flux = Flux.just("1", "2", "3");
        var _456Flux = Flux.just("4", "5", "5");
        return Flux.zip(abcFlux, defFlux, _123Flux, _456Flux)
                .map(t4 -> t4.getT1() + t4.getT2() + t4.getT3() + t4.getT4())
                .log();
    }

    public Mono<String> explore_mergeZipWith_mono() {
        var aMono = Mono.just("A");
        var bMono = Mono.just("B");
        return aMono.zipWith(bMono)
                .map(t2 -> t2.getT1() + t2.getT2())
                .log();
    }

    public static void main(String[] args) throws InterruptedException {
        FluxAndMonoGenerateService service = new FluxAndMonoGenerateService();
        // service.namesFlux().subscribe(System.out::println);

        // service.nameMono().subscribe(System.out::println);
        service.explore_mergeZipWith_mono().subscribe(System.out::println);
        Thread.sleep(3000);
    }
}
