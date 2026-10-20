package demo;

public class App {
    public static void main(String[] args) {
        Repo repo = new Repo();
        repo.save(new Person("Ada", 36));
        repo.findAll().forEach(p -> System.out.println(p.getName()));
    }
}
