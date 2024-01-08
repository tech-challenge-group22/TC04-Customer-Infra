USE CustomerMS;

CREATE TABLE customers (
    id INT auto_increment PRIMARY KEY,
    customer_cpf VARCHAR(11) UNIQUE,
    customer_name VARCHAR(100),
    customer_email VARCHAR(100),
    is_active BOOLEAN NOT NULL
);

SET character_set_client = utf8;
SET character_set_connection = utf8;
SET character_set_results = utf8;
SET collation_connection = utf8_general_ci;

-- CADASTRANDO CLIENTE DEFAULT
INSERT INTO customers (id, customer_name, is_active) VALUES (1, 'unamed_customer', 1);

INSERT INTO customers (customer_name, customer_email, customer_cpf, is_active) VALUES ('Gabriel de Barros Pontes', 'gabrielpontes98@gmail.com', '46272039859', 1);