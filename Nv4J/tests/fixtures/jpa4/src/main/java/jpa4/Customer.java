package jpa4;

import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import java.util.List;

@Entity
public class Customer {
    @Id
    @GeneratedValue
    private Long id;
    private String email;
    private String fullName;
    private boolean active;
    @Embedded
    private Address address;
    @OneToMany(mappedBy = "customer")
    private List<Booking> bookings;

    public Long getId() { return id; }
    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public boolean isActive() { return active; }
    public void setActive(boolean active) { this.active = active; }
    public Address getAddress() { return address; }
    public void setAddress(Address address) { this.address = address; }
    public List<Booking> getBookings() { return bookings; }
    public void setBookings(List<Booking> bookings) { this.bookings = bookings; }
}
