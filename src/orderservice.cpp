#include "common.hpp"

#include <boost/uuid/random_generator.hpp>
#include <boost/uuid/uuid_io.hpp>

#include <chrono>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include <userver/components/minimal_server_component_list.hpp>
#include <userver/engine/deadline.hpp>
#include <userver/formats/json.hpp>
#include <userver/formats/json/serialize.hpp>
#include <userver/formats/json/value_builder.hpp>
#include <userver/http/content_type.hpp>
#include <userver/server/handlers/http_handler_base.hpp>
#include <userver/testsuite/testsuite_support.hpp>
#include <userver/ugrpc/client/call_options.hpp>
#include <userver/ugrpc/client/client_factory_component.hpp>
#include <userver/ugrpc/client/component_list.hpp>
#include <userver/ugrpc/client/simple_client_component.hpp>
#include <userver/utils/daemon_run.hpp>
#include <userver/utils/datetime.hpp>

#include <proto/inventoryserviceapi_client.usrv.pb.hpp>

namespace native_example {

using InventoryClientComponent =
    userver::ugrpc::client::SimpleClientComponent<inventoryserviceapi::InventoryServiceApiClient>;

struct RequestItem final {
  std::string item_id;
  std::string sku;
  int quantity{};
  double unit_price{};
};

struct ItemResult final {
  RequestItem item;
  int available_qty{};
  bool reserved{};
  std::string status;
  std::string error;
};

class ProcessOrderHandler final : public userver::server::handlers::HttpHandlerBase {
 public:
  static constexpr std::string_view kName = "handler-process-order";

  ProcessOrderHandler(const userver::components::ComponentConfig& config,
                      const userver::components::ComponentContext& context)
      : HttpHandlerBase(config, context),
        client_(context.FindComponent<InventoryClientComponent>("inventory-client").GetClient()),
        timeout_(ParseDuration("ORDER_SERVICE_REQUEST_TIMEOUT", std::chrono::seconds{5})),
        soft_margin_(ParseDuration("ORDER_SERVICE_SOFT_DEADLINE_MARGIN", std::chrono::seconds{1})) {
    if (soft_margin_ > timeout_) throw std::runtime_error("soft deadline margin exceeds timeout");
  }

  std::string HandleRequestThrow(
      const userver::server::http::HttpRequest& request,
      userver::server::request::RequestContext&) const override {
    auto& response = request.GetHttpResponse();
    const auto badRequest = [&response](std::string_view message) {
      response.SetStatus(userver::server::http::HttpStatus::kBadRequest);
      response.SetContentType(userver::http::content_type::kTextPlain);
      return std::string{message} + "\n";
    };
    userver::formats::json::Value json;
    try {
      json = userver::formats::json::FromString(request.RequestBody());
    } catch (const std::exception&) {
      return badRequest("invalid JSON body");
    }
    const auto raw_items = json["items"];
    if (!raw_items.IsArray() || raw_items.IsEmpty()) {
      return badRequest("items must not be empty");
    }
    std::vector<RequestItem> items;
    items.reserve(raw_items.GetSize());
    double original_total = 0;
    for (const auto& raw : raw_items) {
      RequestItem item;
      item.item_id = raw.HasMember("item_id") ? raw["item_id"].As<std::string>()
                                             : raw["itemId"].As<std::string>();
      item.sku = raw["sku"].As<std::string>();
      item.quantity = raw["quantity"].As<int>();
      if (item.quantity <= 0) {
        return badRequest("all quantities must be positive");
      }
      if (raw.HasMember("unit_price")) item.unit_price = raw["unit_price"].As<double>();
      if (raw.HasMember("unitPrice")) item.unit_price = raw["unitPrice"].As<double>();
      original_total += item.unit_price * item.quantity;
      items.push_back(std::move(item));
    }

    auto order_id = request.GetHeader("X-Request-ID");
    if (order_id.empty()) order_id = boost::uuids::to_string(boost::uuids::random_generator{}());
    const auto soft_deadline =
        userver::engine::Deadline::FromDuration(timeout_ - soft_margin_);
    std::vector<ItemResult> results;
    results.reserve(items.size());
    for (auto& item : items) {
      if (soft_deadline.IsReached()) {
        response.SetContentType(userver::http::content_type::kApplicationJson);
        return userver::formats::json::ToString(
            MakeResponse(order_id, "TIMED_OUT", original_total, {}));
      }
      try {
        processorderitem::ProcessOrderItemRequest grpc_request;
        grpc_request.set_order_id(order_id);
        grpc_request.set_item_id(item.item_id);
        grpc_request.set_sku(item.sku);
        grpc_request.set_quantity(item.quantity);
        userver::ugrpc::client::CallOptions options;
        options.SetDeadline(soft_deadline);
        auto grpc_response = client_.ProcessOrderItem(grpc_request, std::move(options));
        results.push_back(ItemResult{std::move(item), grpc_response.available_qty(),
                                     grpc_response.reserved(), grpc_response.status(), {}});
      } catch (const std::exception& error) {
        if (soft_deadline.IsReached()) {
          response.SetContentType(userver::http::content_type::kApplicationJson);
          return userver::formats::json::ToString(
              MakeResponse(order_id, "TIMED_OUT", original_total, {}));
        }
        results.push_back(ItemResult{std::move(item), 0, false, "PROCESSING_ERROR", error.what()});
      }
    }

    bool all_reserved = true;
    double total = 0;
    for (const auto& result : results) {
      all_reserved = all_reserved && result.reserved;
      total += result.item.unit_price * result.item.quantity;
    }
    response.SetContentType(userver::http::content_type::kApplicationJson);
    return userver::formats::json::ToString(MakeResponse(
        order_id, all_reserved ? "CONFIRMED" : "PARTIALLY_CONFIRMED", total,
        results));
  }

 private:
  static userver::formats::json::Value MakeResponse(
      const std::string& order_id, std::string_view status, double total,
      const std::vector<ItemResult>& results) {
    userver::formats::json::ValueBuilder response;
    response["order_id"] = order_id;
    response["status"] = status;
    response["total_amount"] = total;
    response["processed_at"] =
        userver::utils::datetime::Timestring(std::chrono::system_clock::now());
    if (!results.empty()) {
      userver::formats::json::ValueBuilder confirmed(userver::formats::json::Type::kArray);
      for (const auto& result : results) {
        userver::formats::json::ValueBuilder item;
        item["item_id"] = result.item.item_id;
        item["sku"] = result.item.sku;
        item["available_qty"] = result.available_qty;
        item["reserved"] = result.reserved;
        item["status"] = result.status;
        if (!result.error.empty()) item["error"] = result.error;
        confirmed.PushBack(item.ExtractValue());
      }
      response["confirmed_items"] = confirmed.ExtractValue();
    }
    return response.ExtractValue();
  }

  inventoryserviceapi::InventoryServiceApiClient& client_;
  std::chrono::milliseconds timeout_;
  std::chrono::milliseconds soft_margin_;
};

}  // namespace native_example

int main(int argc, char* argv[]) {
  auto components = userver::components::MinimalServerComponentList()
                        .Append<userver::components::TestsuiteSupport>()
                        .Append<native_example::DisabledServerMiddlewarePipeline>()
                        .Append<userver::ugrpc::client::ClientFactoryComponent>()
                        .AppendComponentList(userver::ugrpc::client::MinimalComponentList())
                        .Append<native_example::InventoryClientComponent>("inventory-client")
                        .Append<native_example::ProcessOrderHandler>()
                        .Append<native_example::StatusHandler>()
                        .Append<native_example::MetricsHandler>();
  return userver::utils::DaemonMain(argc, argv, components);
}
