require 'sinatra'
require 'killbill_client'

set :kb_url, ENV['KB_URL'] || 'http://127.0.0.1:8080'
set :publishable_key, ENV['PUBLISHABLE_KEY']

#
# Kill Bill configuration and helpers
#

KillBillClient.url = settings.kb_url

# Multi-tenancy and RBAC credentials
options = {
    :username => 'admin',
    :password => 'password',
    :api_key => 'bob',
    :api_secret => 'lazar'
}

# Audit log data
user = 'demo'
reason = 'New subscription'
comment = 'Trigger by Sinatra'

def get_kb_account(id, options)
  KillBillClient::Model::Account.find_by_id(id, false, false, options)
end

def create_kb_account(user, reason, comment, options)
  account = KillBillClient::Model::Account.new
  account.name = 'John Doe'
  account.currency = 'USD'
  account.create(user, reason, comment, options)
end

def create_kb_payment_method(account, paypal_token, user, reason, comment, options)
  pm = KillBillClient::Model::PaymentMethod.new
  pm.account_id = account.account_id
  pm.plugin_name = 'killbill-paypal-express'
  pm.plugin_info = {'token' => paypal_token}
  pm.create(true, user, reason, comment, options)
end

def create_subscription(account, user, reason, comment, options)
  subscription = KillBillClient::Model::Subscription.new
  subscription.account_id = account.account_id
  subscription.product_name = 'Sports'
  subscription.product_category = 'BASE'
  subscription.billing_period = 'MONTHLY'
  subscription.price_list = 'DEFAULT'
  subscription.price_overrides = []

  # For the demo to be interesting, override the trial price to be non-zero so we trigger a charge in PayPal
  override_trial = KillBillClient::Model::PhasePriceOverrideAttributes.new
  override_trial.phase_type = 'TRIAL'
  override_trial.fixed_price = 10.0
  subscription.price_overrides << override_trial

  subscription.create(user, reason, comment, nil, false, options)
  # TODO Specify callTimeoutSec
  sleep 8
end

def generate_redirect(account, options)
  KillBillClient::Model::Resource.post('/plugins/killbill-paypal-express/1.0/setup-checkout',
                                       {
                                         :kb_account_id => account.account_id,
                                         :currency => account.currency,
                                         :options => {
                                           :return_url => "http://localhost:4567/charge?q=SUCCESS&accountId=#{account.account_id}",
                                           :cancel_return_url => "http://localhost:4567/charge?q=FAILURE&accountId=#{account.account_id}",
                                           :billing_agreement => {
                                             :description => "Your subscription"
                                           }
                                         }
                                       }.to_json,
                                       {},
                                       options)
rescue => e
  e.response['Location']
end

#
# Sinatra handlers
#

get '/' do
  erb :index
end

get '/redirect' do
  # Create an account
  account = create_kb_account(user, reason, comment, options)

  # Redirect the user to PayPal
  redirect to(generate_redirect(account, options))
end

get '/charge' do
  account = get_kb_account(params[:accountId], options)

  # Add a payment method associated with the PayPal token
  create_kb_payment_method(account, params[:token], user, reason, comment, options)

  # Add a subscription
  create_subscription(account, user, reason, comment, options)

  # Retrieve the invoice
  @invoice = account.invoices(true, options).first

  erb :charge
end

__END__

@@ layout
  <!DOCTYPE html>
  <html>
  <head></head>
  <body>
    <%= yield %>
  </body>
  </html>

@@index
  <span class="image"><img src="https://drive.google.com/uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480" alt="uc?&amp;id=0Bw8rymjWckBHT3dKd0U3a1RfcUE&amp;w=960&amp;h=480"></span>
  <form action="/charge" method="post">
    <article>
      <label class="amount">
        <span>Sports car, 30 days trial for only $10.00!</span>
      </label>
    </article>
    <br/>
    <a href="/redirect">Pay with PayPal</a>
  </form>

@@charge
  <h2>Thanks! Here is your invoice:</h2>
  <ul>
    <% @invoice.items.each do |item| %>
      <li><%= "subscription_id=#{item.subscription_id}, amount=#{item.amount}, phase=sports-monthly-trial, start_date=#{item.start_date}" %></li>
    <% end %>
  </ul>
