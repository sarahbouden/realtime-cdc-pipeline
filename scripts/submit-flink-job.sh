#!/bin/bash
# =============================================================================
# submit-flink-job.sh
# Submits the CDC processor job to the Flink cluster.
#
# Flink runs in session mode — the cluster stays up, you submit jobs to it.
# This mirrors how production Flink deployments work on YARN or Kubernetes.
# =============================================================================

FLINK_JOBMANAGER="cdc_flink_jobmanager"

echo "Submitting CDC processor job to Flink..."
docker exec -it ${FLINK_JOBMANAGER} \
    flink run \
    --python /opt/flink/jobs/cdc_processor.py \
    --pyFiles /opt/flink/jobs/

echo ""
echo "Job submitted. Monitor at: http://localhost:8082"
echo "You should see 1 running job in the Flink dashboard."