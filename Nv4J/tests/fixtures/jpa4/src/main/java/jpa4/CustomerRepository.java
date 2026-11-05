package jpa4;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface CustomerRepository extends JpaRepository<Customer, Long> {
    Optional<Customer> findByEmail(String email);

    List<Customer> findByFullNameContainingIgnoreCase(String part);

    List<Customer> findByAddressCity(String city);

    @Query("select c from Customer c where c.active = true order by c.fullName")
    List<Customer> activeCustomers();
}
