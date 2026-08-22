#include "common.hpp"

#include <atomic>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>

#include <userver/components/minimal_server_component_list.hpp>
#include <userver/engine/sleep.hpp>
#include <userver/ugrpc/server/component_list.hpp>
#include <userver/utils/daemon_run.hpp>

#include <proto/inventoryserviceapi_service.usrv.pb.hpp>

namespace native_example {

class InventoryService final : public inventoryserviceapi::InventoryServiceApiBase::Component {
 public:
  static constexpr std::string_view kName = "inventory-service-api";

  InventoryService(const userver::components::ComponentConfig& config,
                   const userver::components::ComponentContext& context)
      : InventoryServiceApiBase::Component(config, context),
        delay_(ParseDuration("INVENTORY_SERVICE_RESPONSE_DELAY", std::chrono::milliseconds{0})) {}

  ProcessOrderItemResult ProcessOrderItem(
      CallContext&, processorderitem::ProcessOrderItemRequest&& request) override {
    if (delay_.count() > 0) userver::engine::SleepFor(delay_);
    auto iter = stock_.find(request.sku());
    auto available = iter == stock_.end()
                         ? 0
                         : iter->second->load(std::memory_order_relaxed);
    bool reserved = false;
    while (iter != stock_.end() && available >= request.quantity()) {
      if (iter->second->compare_exchange_weak(
              available, available - request.quantity(),
              std::memory_order_relaxed, std::memory_order_relaxed)) {
        reserved = true;
        break;
      }
    }

    processorderitem::ProcessOrderItemResponse response;
    response.set_available_qty(reserved ? request.quantity() : available);
    response.set_reserved(reserved);
    response.set_status(reserved ? "CONFIRMED" : "OUT_OF_STOCK");
    return response;
  }

 private:
  std::unordered_map<std::string, std::shared_ptr<std::atomic<int>>> stock_{
      {"SKU-001", std::make_shared<std::atomic<int>>(100)},
      {"SKU-002", std::make_shared<std::atomic<int>>(50)},
      {"SKU-003", std::make_shared<std::atomic<int>>(25)}};
  std::chrono::milliseconds delay_;
};

}  // namespace native_example

int main(int argc, char* argv[]) {
  auto components = userver::components::MinimalServerComponentList()
                        .Append<native_example::DisabledServerMiddlewarePipeline>()
                        .AppendComponentList(userver::ugrpc::server::MinimalComponentList())
                        .Append<native_example::InventoryService>()
                        .Append<native_example::StatusHandler>()
                        .Append<native_example::MetricsHandler>();
  return userver::utils::DaemonMain(argc, argv, components);
}
