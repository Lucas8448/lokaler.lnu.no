# frozen_string_literal: true

class Space < ApplicationRecord
  has_paper_trail skip: [:star_rating]

  has_many_attached :images
  has_many :facility_reviews, dependent: :restrict_with_exception
  has_many :aggregated_facility_reviews, dependent: :restrict_with_exception
  has_many :reviews, dependent: :restrict_with_exception

  belongs_to :space_owner
  accepts_nested_attributes_for :space_owner
  scope :filter_on_space_types, ->(space_type_ids) { where(space_type_id: space_type_ids) }
  scope :filter_on_location, lambda { |north_west_lat, north_west_lng, south_east_lat, south_east_lng|
    where(":north_west_lat >= lat AND :north_west_lng <= lng AND :south_east_lat <= lat AND :south_east_lng >= lng",
          north_west_lat: north_west_lat,
          north_west_lng: north_west_lng,
          south_east_lat: south_east_lat,
          south_east_lng: south_east_lng)
  }

  belongs_to :space_type

  has_rich_text :how_to_book
  has_rich_text :who_can_use
  has_rich_text :pricing
  has_rich_text :terms
  has_rich_text :more_info

  validates :star_rating, numericality: { greater_than: 0, less_than: 6 }, allow_nil: true

  after_create do
    aggregate_facility_reviews
    aggregate_star_rating
  end

  def reviews_for_facility(facility)
    AggregatedFacilityReview.find_by(space: self, facility: facility).experience
  end

  def facilities_in_category(category)
    AggregatedFacilityReview
      .includes(:facility)
      .where(space: self, facilities: { facility_category: category })
      .map do |result|
      {
        title: result.facility.title,
        icon: result.facility.icon,
        review: result.experience
      }
    end
  end

  def self.rect_of_spaces
    south_west_lat = 90
    south_west_lng = 180

    north_east_lat = -90
    north_east_lng = -180

    # Eventually this method will take some search parameters
    # but currently we just use the all the spaces in the db
    Space.all.find_each do |space|
      south_west_lat = space.lat if space.lat < south_west_lat
      south_west_lng = space.lng if space.lng < south_west_lng
      north_east_lat = space.lat if space.lat > north_east_lat
      north_east_lng = space.lng if space.lng > north_east_lng
    end

    { south_west: { lat: south_west_lat, lng: south_west_lng },
      north_east: { lat: north_east_lat, lng: north_east_lng } }
  end

  def aggregate_facility_reviews
    Spaces::AggregateFacilityReviewsService.call(space: self)
  end

  def aggregate_star_rating
    Spaces::AggregateStarRatingService.call(space: self)
  end

  def self.search_for_address(address:, post_number:, post_address:)
    results = Spaces::LocationSearchService.call(
      address: address,
      post_number: post_number,
      post_address: post_address
    )

    return nil if results.count > 1 || results.empty?

    results.first
  end

  # Move this somewhere better, either a service or figure out a way to make it a scope
  # NOTE: this expects a scope for spaces but returns an array
  # preferably we would find some way to return a scope too
  def self.filter_on_facilities(spaces, facilities) # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
    results = spaces.includes(:aggregated_facility_reviews).filter_map do |space|
      score = 0
      space.aggregated_facility_reviews.each do |review|
        next unless facilities.include?(review.facility_id)

        # The more correct matches the lower the number.
        # this is so the sort_by later will be correct as it sorts by lowest first
        # we could do a reverse on the result of sort_by but this will incur
        # a performance overhead
        if review.maybe? || review.likely?
          score -= 1
        elsif review.impossible?
          score += 1
        end
      end

      OpenStruct.new(score: score, space: space)
    end

    results.sort_by(&:score).map(&:space)
  end

  def star_rating_s
    star_rating || " - "
  end
end
