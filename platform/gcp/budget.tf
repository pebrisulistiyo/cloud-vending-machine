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

  # No all_updates_rule: alerts go to the billing account's default IAM
  # recipients (the account owner). A pubsub_topic for custom delivery is
  # the obvious upgrade if a second watcher joins.
}
