-- Account-wide seasons; all state starts empty and is created explicitly by a GM.

CREATE TABLE IF NOT EXISTS `coa_season` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(64) NOT NULL,
    `status` VARCHAR(8) NOT NULL DEFAULT 'draft',
    `revision` INT UNSIGNED NOT NULL DEFAULT 1,
    `created` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `activated` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_settings` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `key` VARCHAR(32) NOT NULL,
    `value` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_tier` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `threshold` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_tier_reward` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `type` VARCHAR(16) NOT NULL,
    `target` INT UNSIGNED NOT NULL DEFAULT 0,
    `preview` INT UNSIGNED NOT NULL DEFAULT 0,
    `count` INT UNSIGNED NOT NULL DEFAULT 1,
    `name` VARCHAR(48) NOT NULL,
    PRIMARY KEY (`season`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_account` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `account` INT UNSIGNED NOT NULL DEFAULT 0,
    `points` INT UNSIGNED NOT NULL DEFAULT 0,
    `mask` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `account`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_tier_grant` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `account` INT UNSIGNED NOT NULL DEFAULT 0,
    `tier` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `character_guid` INT UNSIGNED NOT NULL DEFAULT 0,
    `type` VARCHAR(16) NOT NULL,
    `target` INT UNSIGNED NOT NULL DEFAULT 0,
    `count` INT UNSIGNED NOT NULL DEFAULT 1,
    `created` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `account`, `tier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_daily_kill` (
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `account` INT UNSIGNED NOT NULL DEFAULT 0,
    `entry` INT UNSIGNED NOT NULL DEFAULT 0,
    `last_time` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`season`, `account`, `entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_level_reward` (
    `character_guid` INT UNSIGNED NOT NULL DEFAULT 0,
    `highest_level` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`character_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_request` (
    `account` INT UNSIGNED NOT NULL DEFAULT 0,
    `request_id` VARCHAR(32) CHARACTER SET `ascii` COLLATE `ascii_bin` NOT NULL,
    `payload` VARCHAR(245) CHARACTER SET `ascii` COLLATE `ascii_bin` NOT NULL,
    `response` VARCHAR(245) CHARACTER SET `ascii` COLLATE `ascii_bin` NOT NULL,
    `created` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account`, `request_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `coa_season_audit` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `season` INT UNSIGNED NOT NULL DEFAULT 0,
    `account` INT UNSIGNED NOT NULL DEFAULT 0,
    `action` VARCHAR(160) NOT NULL,
    `created` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    KEY `season_history` (`season`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `account_appearance_collection` (
    `account_id` INT UNSIGNED NOT NULL,
    `appearance_id` INT UNSIGNED NOT NULL,
    `source_item` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`account_id`, `appearance_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `account_vanity_collection` (
    `account_id` INT UNSIGNED NOT NULL,
    `item_id` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`account_id`, `item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
