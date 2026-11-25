# Incident write-ups

After a drill, copy [TEMPLATE.md](TEMPLATE.md) to
`incidents/YYYY-MM-DD-<drill>.md`. Fill it in with observations from the
live run while the timeline is fresh.

- Include the Git revision, dashboard time ranges, and relevant Kubernetes
  events or logs. Redact any credentials and customer information.
- Use Australia/Sydney timestamps with an explicit UTC offset. Capture
  the change, the first symptom, detection, rollback, and recovery.
- Measure impact from eligible requests. For availability, count 5xx
  responses. For latency, subtract the count in `le="0.3"` from all
  histogram observations. Use the SLO selector in both cases.
- To estimate the fraction of the 30-day error budget spent during the
  incident, divide incident bad requests by total eligible requests over
  30 days times the budget fraction. Use 0.005 for availability and 0.01
  for latency. If the cluster has less history, give the actual coverage
  and separate observed sample counts from any projection.
- Describe the system conditions that allowed the incident. Give each
  follow-up an owner and a way to verify that it worked.
