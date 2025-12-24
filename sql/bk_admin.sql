CREATE TABLE `bk_admin` (
	`citizenid` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	`rank` VARCHAR(20) NULL DEFAULT 'user' COLLATE 'utf8mb4_uca1400_ai_ci',
	`identifiers` LONGTEXT NULL DEFAULT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	`last_seen` DATETIME NULL DEFAULT current_timestamp(),
	PRIMARY KEY (`citizenid`) USING BTREE
)
COLLATE='utf8mb4_uca1400_ai_ci'
ENGINE=InnoDB
;
