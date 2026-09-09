# The GCP counterpart of the AWS budgets in terraform-bootstrap: $10/mo
# guardrail, alerts at 50/90/100%. Everything in this project fits in the
# free tier at demo volume, if this budget fires, something is running
# that shouldn't be.
resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account_id
  display_name    = "portfolio-10usd"

  amount {
    specified_amount {
      currency_code = "USD"
      units         = "10"
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.9
  }
  threshold_rules {
    threshold_percent = 1.0
  }

  all_updates_rule {
    monitoring_notification_channels = [
      google_monitoring_notification_channel.budget_email.id,
    ]
    disable_default_iam_recipients = false
  }
}

resource "google_monitoring_notification_channel" "budget_email" {
  project      = var.gcp_project_id
  display_name = "Budget Alert Email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
  depends_on = [google_project_service.apis]
}
