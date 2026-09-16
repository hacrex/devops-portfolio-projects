package com.hacrex.capstone.repository;

import com.hacrex.capstone.model.Order;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepository extends JpaRepository<Order, Long> {
}
