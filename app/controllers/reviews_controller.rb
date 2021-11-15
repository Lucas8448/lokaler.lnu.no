# frozen_string_literal: true

class ReviewsController < AuthenticateController # rubocop:disable Metrics/ClassLength
  def index
    @reviews = Review.all
    @review = Review.new
  end

  def show
    @review = Review.find(params[:id])
  end

  def create
    params = parse_before_create review_params
    @review = Review.new(params)
    if @review.save
      create_success
    else
      create_error
    end
  end

  def new
    new_review_attributes
  end

  def new_with_type_of_contact
    new_review_attributes
    @review.type_of_contact = params[:type_of_contact]
    render "new_#{params[:type_of_contact]}"
  end

  def edit
    @review = Review.find(params[:id])
    @space = @review.space
    common_review_attributes
  end

  def update
    @review = Review.find(params[:id])
    @space = @review.space

    common_review_attributes
    params = parse_before_update(review_params, @review)

    if @review.update(params)
      redirect_to reviews_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def create_success
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.prepend(:reviews,
                               partial: "spaces/show/review_card",
                               locals: { review: @review }),
          turbo_stream.replace(:new_review_path,
                               partial: "spaces/show/review_link_to_new_review",
                               locals: {
                                 space: @review.space
                               })
        ]
      end
      format.html { redirect_to @review.space }
    end
  end

  def create_error
    @space = @review.space
    common_review_attributes
    # Different types of contact should be sent to different error forms
    case @review.type_of_contact
    when "been_there"
      render :new_been_there, status: :unprocessable_entity
    when "not_allowed_to_use"
      render :new_not_allowed_to_use, status: :unprocessable_entity
    when "only_contacted"
      render :new_only_contacted, status: :unprocessable_entity
    else
      render :new, status: :unprocessable_entity
    end
  end

  def new_review_attributes
    @space = Space.find(params[:space_id]) unless defined? @review
    @review = Review.new(space: @space) unless defined? @review
    common_review_attributes
  end

  def common_review_attributes
    @facility_reviews = @space.aggregated_facility_reviews
  end

  def parse_before_update(review_params, review)
    review_params["facility_reviews_attributes"] = parse_facility_reviews(
      review_params["facility_reviews_attributes"],
      review
    )
    review_params
  end

  def parse_before_create(review_params)
    review_params["facility_reviews_attributes"] = parse_facility_reviews(review_params["facility_reviews_attributes"])
    review_params["user"] = current_user
    review_params
  end

  def parse_facility_reviews(facility_reviews, review = nil)
    # Converting to .values exists solely because I didn't manage to create a
    # form with radio buttons that sent the facility_reviews in a way that could
    # be automatically picked up by Rails AND still be seen as individual in the form itself.
    # Thus, we have to parse what is sent from the form here into something
    # that more closely resembles what the model expects:
    # Changes welcome!
    facility_review_values = facility_reviews.values

    known_reviews = delete_all_unknown facility_review_values
    add_user_and_space known_reviews, review
  end

  # Facility Reviews only not need a user or space attached, as
  # they are attached to reviews, who have both of those already.
  # However, refactoring that means changing a lot of how
  # facility reviews are calculated. Feel free to submit a PR if you
  # want to!
  #
  # In the meantime, this code makes sure that we have user and space
  # set, even though the form doesn't send them for each facility review.
  def add_user_and_space(facility_reviews, review = nil)
    facility_reviews.map do |facility_review|
      facility_review[:user] = review&.user ? review.user : current_user
      facility_review[:space_id] = review&.space&.id ? review.space.id : review_params["space_id"]
      facility_review
    end
  end

  # This should be done in the model, but I never figured out how.
  # I tried to .destroy and filter on before_validation, but
  # it only got roll-backed.
  def delete_all_unknown(facility_reviews)
    ids = facility_reviews.filter_map { |review| review[:id] if review[:experience] == "unknown" }
    FacilityReview.where(id: ids).destroy_all

    facility_reviews.delete_if { |review| review[:experience] == "unknown" }
  end

  def review_params
    params.require(:review).permit(
      :title, :comment,
      :price, :star_rating,
      :how_much, :how_much_custom,
      :how_long, :how_long_custom,
      :type_of_contact,
      :space_id,
      facility_reviews_attributes: %i[facility_id experience id]
    )
  end
end
