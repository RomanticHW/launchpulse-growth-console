module Api
  module V1
    class EventsController < ActionController::API
      def create
        event = Events::IngestionService.new(params: event_params.to_h.symbolize_keys, request:).call
        render json: { id: event.id, status: "accepted" }, status: :accepted
      rescue Events::IngestionService::InvalidToken => error
        render json: { error: error.message }, status: :unauthorized
      rescue Events::IngestionService::InvalidPayload, ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
        render json: { error: error.message }, status: :unprocessable_content
      end

      private

      def event_params
        permitted = params.permit(:site_token, :event_type, :visitor_id, :session_id, :source, :device, :section_uid, :experiment_id, :variant_key, :page_path, :occurred_at, :idempotency_key)
        # metadata 的结构校验集中交给 MetadataSanitizer；controller 只控制顶层业务字段。
        attrs = permitted.to_h
        attrs.merge!(metadata: params[:metadata]) if params.key?(:metadata)
        attrs
      end
    end
  end
end
