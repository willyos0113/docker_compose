USE testdb;

CREATE TABLE Product (
    Id INT NOT NULL AUTO_INCREMENT PRIMARY KEY COMMENT '產品編號',
    Name VARCHAR(100) NOT NULL COMMENT '產品名稱',
    Price DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '售價',
    Stock INT NOT NULL DEFAULT 0 COMMENT '庫存數量',
    CreatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '建立時間'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='產品資料表';


INSERT INTO Product (Name, Price, Stock) VALUES
    ('Bluetooth Headphones', 1290.00, 50),
    ('USB-C Cable', 299.00, 150),
    ('Mechanical Keyboard', 2490.00, 30);

SELECT * FROM Product;
SELECT Name, Price FROM Product WHERE Price > 1000;
UPDATE Product SET Price = 1190.00 WHERE Name = 'Bluetooth Headphones';
DELETE FROM Product WHERE Name = 'USB-C Cable';
