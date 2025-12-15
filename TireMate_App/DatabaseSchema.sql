-- =============================================
-- ระบบบริหารจัดการสต็อกร้านยาง (Tire Shop System)
-- Database Schema Update: รองรับ EV Type & Country of Origin
-- =============================================

-- 1. ตารางสาขา (Branches)
CREATE TABLE Branches (
    branch_id INT PRIMARY KEY AUTO_INCREMENT,
    branch_name VARCHAR(100) NOT NULL,
    location TEXT,
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. ตารางข้อมูลยาง (Tires Master)
-- เก็บข้อมูลสินค้าที่เป็น Master Data (ข้อมูลดิบของรุ่นยาง ไม่เกี่ยวกับจำนวนสต็อก)
CREATE TABLE Tires (
    tire_id INT PRIMARY KEY AUTO_INCREMENT,
    sku VARCHAR(50) UNIQUE NOT NULL,           -- รหัสสินค้า (เช่น BS-2656018-T005A)
    brand VARCHAR(50) NOT NULL,                -- ยี่ห้อ (Bridgestone, Michelin)
    model_name VARCHAR(100) NOT NULL,          -- ชื่อรุ่น (Turanza T005A)
    
    -- สเปคยาง
    width INT NOT NULL,                        -- หน้ากว้าง (265)
    series INT NOT NULL,                       -- ซีรีส์ (60)
    rim INT NOT NULL,                          -- ขอบ (18)
    
    -- [New Feature] ประเภทของยาง
    tire_type ENUM('STANDARD', 'EV', 'FUEL_SAVE', 'RUNFLAT') DEFAULT 'STANDARD', 
    
    -- ราคา
    wholesale_price DECIMAL(10, 2) NOT NULL,   -- ราคาขายส่ง (สำหรับ Chatbot ตอบลูกค้า)
    retail_price DECIMAL(10, 2) NOT NULL,      -- ราคาหน้าร้าน
    
    image_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 3. ตารางสต็อกตามล็อต (InventoryLots) *** หัวใจของระบบ FIFO ***
-- แยกเก็บยางแต่ละชุดที่รับเข้ามา เพื่อให้รู้ว่าเส้นไหนเก่า/ใหม่ และมาจากประเทศไหน
CREATE TABLE InventoryLots (
    lot_id INT PRIMARY KEY AUTO_INCREMENT,
    tire_id INT NOT NULL,
    branch_id INT NOT NULL,
    
    -- [New Feature] ข้อมูลเฉพาะของล็อต (ใช้ระบุตัวตนสินค้าตอนรับเข้า)
    production_week INT NOT NULL,              -- สัปดาห์ที่ผลิต (เช่น 35)
    production_year INT NOT NULL,              -- ปีที่ผลิต (เช่น 2024)
    country_of_origin VARCHAR(50) NOT NULL,    -- ประเทศที่ผลิต (Thailand, Japan)
    cost_price DECIMAL(10, 2) NOT NULL,        -- ราคาทุนจริงของล็อตนี้
    
    -- การจัดการจำนวน (Inventory Control)
    initial_quantity INT NOT NULL,             -- จำนวนที่รับเข้าตอนแรก
    current_quantity INT NOT NULL,             -- จำนวนคงเหลือปัจจุบัน (ลดลงเมื่อขาย)
    
    received_date DATE NOT NULL,               -- วันที่รับของเข้าสาขา
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (tire_id) REFERENCES Tires(tire_id),
    FOREIGN KEY (branch_id) REFERENCES Branches(branch_id)
);

-- Index ช่วยค้นหาล็อตที่จะขายก่อน (FIFO) ได้เร็วที่สุด
-- หลักการ: เรียงตาม ปีผลิต(น้อยสุด) -> สัปดาห์ผลิต(น้อยสุด) -> วันที่รับของ(มาก่อน)
CREATE INDEX idx_fifo_sort ON InventoryLots (tire_id, branch_id, production_year ASC, production_week ASC, received_date ASC);

-- 4. ตารางประวัติธุรกรรม (StockTransactions)
-- เก็บ Log การเคลื่อนไหวทุกอย่าง (เข้า/ออก/โอน) เพื่อตรวจสอบย้อนหลัง
CREATE TABLE StockTransactions (
    transaction_id INT PRIMARY KEY AUTO_INCREMENT,
    lot_id INT NOT NULL,                       -- อ้างอิงว่าทำรายการกับล็อตไหน
    
    -- ประเภทรายการ
    transaction_type ENUM('STOCK_IN', 'SALE', 'TRANSFER_OUT', 'TRANSFER_IN', 'ADJUST', 'RETURN') NOT NULL,
    
    quantity_change INT NOT NULL,              -- จำนวนที่เปลี่ยนแปลง (ติดลบ = ออก, บวก = เข้า)
    reference_doc VARCHAR(50),                 -- เลขที่เอกสารอ้างอิง (เช่น INV-2025-001)
    user_id INT,                               -- รหัสพนักงานที่ทำรายการ
    note TEXT,                                 -- หมายเหตุเพิ่มเติม
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (lot_id) REFERENCES InventoryLots(lot_id)
);

-- 5. ตารางแจ้งเตือนสต็อก (StockAlerts)
-- ใช้สำหรับตั้งค่า Minimum Stock แยกรายสาขา
CREATE TABLE StockAlerts (
    alert_id INT PRIMARY KEY AUTO_INCREMENT,
    tire_id INT NOT NULL,
    branch_id INT NOT NULL,
    minimum_level INT NOT NULL DEFAULT 4,      -- จุดสั่งซื้อ (Reorder Point)
    
    FOREIGN KEY (tire_id) REFERENCES Tires(tire_id),
    FOREIGN KEY (branch_id) REFERENCES Branches(branch_id),
    UNIQUE(tire_id, branch_id)                 -- ป้องกันการตั้งค่าซ้ำซ้อน
);

-- =============================================
-- ตัวอย่างการ Query ข้อมูล
-- =============================================

-- 1. ดูยอดคงเหลือรวม แยกตามรุ่น (สำหรับหน้า Dashboard)
-- SELECT t.sku, t.model_name, SUM(l.current_quantity) as total_stock
-- FROM Tires t
-- JOIN InventoryLots l ON t.tire_id = l.tire_id
-- WHERE l.branch_id = 1
-- GROUP BY t.tire_id;

-- 2. หาล็อตที่ต้องตัดสต็อกก่อน (FIFO Logic)
-- SELECT * FROM InventoryLots
-- WHERE tire_id = ? AND branch_id = ? AND current_quantity > 0
-- ORDER BY production_year ASC, production_week ASC, received_date ASC;