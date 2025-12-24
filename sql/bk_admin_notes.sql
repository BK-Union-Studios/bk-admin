CREATE TABLE `bk_admin_notes` (
	`id` INT(11) NOT NULL AUTO_INCREMENT,
	`citizenid` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	`note` TEXT NOT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	`author` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	`date` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_uca1400_ai_ci',
	PRIMARY KEY (`id`) USING BTREE,
	INDEX `citizenid` (`citizenid`) USING BTREE
)
COLLATE='utf8mb4_uca1400_ai_ci'
ENGINE=InnoDB
AUTO_INCREMENT=4
;