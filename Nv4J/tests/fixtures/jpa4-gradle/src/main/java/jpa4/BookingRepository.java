package jpa4;

import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface BookingRepository extends JpaRepository<Booking, Long> {
    @Query("SELECT b FROM Booking b JOIN FETCH b.customer c WHERE c.email = :email AND b.deletedAt IS NULL")
    List<Booking> findActiveByCustomerEmail(@Param("email") String email);

    @Query("""
            SELECT b FROM Booking b
             WHERE b.customer.id = :customerId AND b.status = :status
            """)
    List<Booking> findByCustomerAndStatus(@Param("customerId") Long customerId, @Param("status") String status);
}
