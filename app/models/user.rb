class User < ApplicationRecord
  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i

  attr_accessor :remember_token, :current_password,
    :activation_token, :reset_token

  enum role: [:user, :admin]
  enum gender: [:female, :male, :other]

  has_many :microposts, dependent: :destroy
  has_many :active_relationships, class_name: :Relationship,
    foreign_key: :follower_id, dependent: :destroy
  has_many :passive_relationships, class_name: :Relationship,
    foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :active_relationships, source: :followed
  has_many :followers, through: :passive_relationships, source: :follower

  validates :name, presence: true,
    length: {maximum: Settings.user.max_length_name}
  validates :email, presence: true,
    length: {maximum: Settings.user.max_length_email},
    format: {with: VALID_EMAIL_REGEX},
    uniqueness: {case_sensitive: false}
  has_secure_password
  validates :password, presence: true, allow_nil: true,
    length: {maximum: Settings.user.max_length_name}

  validates :current_password, presence: true, allow_nil: true

  before_save :downcase_email
  before_create :create_activation_digest

  scope :order_id, -> {order id: :ASC}

  class << self
    def digest string
      if ActiveModel::SecurePassword.min_cost
        cost = BCrypt::Engine::MIN_COST
      else
        cost = BCrypt::Engine.cost
      end
      BCrypt::Password.create string, cost: cost
    end

    def new_token
      SecureRandom.urlsafe_base64
    end
  end

  def authenticated? attribute, token
    digest = self.send "#{attribute}_digest"
    return false unless digest.present?
    BCrypt::Password.new(digest).is_password? token
  end

  def remember
    self.remember_token = User.new_token
    update_attributes remember_digest: User.digest(remember_token)
  end

  def forget
    update_attributes remember_digest: nil
  end

  def send_change_password_mail
    UserMailer.change_password(self).deliver_now
  end

  def send_activation_email
    UserMailer.account_activation(self).deliver_now
  end

  def send_password_reset_email
    UserMailer.password_reset(self).deliver_now
  end

  def activate
    update_columns activated: true, activation_digest: nil,
      activated_at: Time.zone.now
  end

  def activated?
    self.activated
  end

  def create_reset_digest
    self.reset_token = User.new_token
    update_columns reset_digest: User.digest(reset_token),
      reset_sent_at: Time.zone.now
  end

  def password_reset_expired?
    reset_sent_at < Settings.user.password_reset_expire.hours.ago
  end

  def password_present? password
    unless password.present?
      errors[:password] << I18n.t("user.password_present.error")
    end
    return true unless errors.any?
  end

  def follow  other_user
    following << other_user
  end

  def unfollow other_user
    following.delete other_user
  end

  def following? other_user
    following.include? other_user
  end

  def feed
    Micropost.feed_by_following following.ids, id
  end

  private

  def downcase_email
    email.downcase!
  end

  def create_activation_digest
    self.activation_token = User.new_token
    self.activation_digest = User.digest activation_token
  end
end
