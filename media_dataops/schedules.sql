-- Suspend all tasks root -> child before CREATE OR ALTER
ALTER TASK IF EXISTS run_media_dataops_subset SUSPEND;
ALTER TASK IF EXISTS run_media_dataops_full SUSPEND;
ALTER TASK IF EXISTS test_media_dataops SUSPEND;

-- Subset run: early availability for business-critical models
CREATE OR ALTER TASK run_media_dataops_subset
  WAREHOUSE = MEDIA_WH_XS
  SCHEDULE = '12 hours'
AS
  EXECUTE DBT PROJECT media_dataops_dbt_object_gh_action
    ARGS = 'run --select media_events --target prod';

-- Full project run after subset completes
CREATE OR ALTER TASK run_media_dataops_full
  WAREHOUSE = MEDIA_WH_MD
  AFTER run_media_dataops_subset
AS
  EXECUTE DBT PROJECT media_dataops_dbt_object_gh_action
    ARGS = 'run --target prod';

-- Data quality tests after full run
CREATE OR ALTER TASK test_media_dataops
  WAREHOUSE = MEDIA_WH_XS
  AFTER run_media_dataops_full
AS
  EXECUTE DBT PROJECT media_dataops_dbt_object_gh_action
    ARGS = 'test --target prod';

-- Resume tasks in reverse order: child -> root
ALTER TASK IF EXISTS test_media_dataops RESUME;
ALTER TASK IF EXISTS run_media_dataops_full RESUME;
ALTER TASK IF EXISTS run_media_dataops_subset RESUME;
