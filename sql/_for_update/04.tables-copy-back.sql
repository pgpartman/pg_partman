INSERT INTO @extschema@.part_config (
    parent_table
    , control
    , partition_interval
    , partition_type
    , premake
    , automatic_maintenance
    , template_table
    , retention
    , retention_schema
    , retention_keep_index
    , retention_keep_table
    , epoch
    , constraint_cols
    , optimize_constraint
    , infinite_time_partitions
    , datetime_string
    , jobmon
    , sub_partition_set_full
    , undo_in_progress
    , inherit_privileges
    , constraint_valid
    , subscription_refresh
    , ignore_default_data
)
SELECT
    parent_table
    , control
    , partition_interval
    , CASE WHEN partition_type = 'native' THEN 'range' ELSE partition_type END
    , premake
    , automatic_maintenance
    , template_table
    , retention
    , retention_schema
    , retention_keep_index
    , retention_keep_table
    , epoch
    , constraint_cols
    , optimize_constraint
    , infinite_time_partitions
    , datetime_string
    , jobmon
    , sub_partition_set_full
    , undo_in_progress
    , inherit_privileges
    , constraint_valid
    , subscription_refresh
    , ignore_default_data
FROM @extschema@.part_config_pre_500_data;


INSERT INTO @extschema@.part_config_sub (
    sub_parent
    , sub_control
    , sub_partition_interval
    , sub_partition_type
    , sub_premake
    , sub_automatic_maintenance
    , sub_template_table
    , sub_retention
    , sub_retention_schema
    , sub_retention_keep_index
    , sub_retention_keep_table
    , sub_epoch
    , sub_constraint_cols
    , sub_optimize_constraint
    , sub_infinite_time_partitions
    , sub_jobmon
    , sub_inherit_privileges
    , sub_constraint_valid
    , sub_subscription_refresh
    , sub_date_trunc_interval
    , sub_ignore_default_data
)
SELECT
    sub_parent
    , sub_control
    , sub_partition_interval
    , CASE WHEN sub_partition_type = 'native' THEN 'range' ELSE sub_partition_type END
    , sub_premake
    , sub_automatic_maintenance
    , sub_template_table
    , sub_retention
    , sub_retention_schema
    , sub_retention_keep_index
    , sub_retention_keep_table
    , sub_epoch
    , sub_constraint_cols
    , sub_optimize_constraint
    , sub_infinite_time_partitions
    , sub_jobmon
    , sub_inherit_privileges
    , sub_constraint_valid
    , sub_subscription_refresh
    , sub_date_trunc_interval
    , sub_ignore_default_data
FROM @extschema@.part_config_sub_pre_500_data;
