#pragma once

#include <chrono>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <string_view>

#include <userver/server/handlers/http_handler_base.hpp>
#include <userver/server/middlewares/configuration.hpp>

namespace native_example {

class DisabledServerMiddlewarePipeline final
    : public userver::server::middlewares::PipelineBuilder {
 public:
  static constexpr std::string_view kName =
      "native-disabled-server-middlewares";
  using PipelineBuilder::PipelineBuilder;

  userver::server::middlewares::MiddlewaresList BuildPipeline(
      userver::server::middlewares::MiddlewaresList) const override {
    return {};
  }
};

inline std::chrono::milliseconds ParseDuration(const char* name,
                                               std::chrono::milliseconds fallback) {
  const char* raw = std::getenv(name);
  if (!raw || !*raw) return fallback;
  std::string value{raw};
  double multiplier = 1000.0;
  if (value.ends_with("ms")) {
    multiplier = 1.0;
    value.resize(value.size() - 2);
  } else if (value.ends_with('s')) {
    value.pop_back();
  } else if (value.ends_with('m')) {
    multiplier = 60000.0;
    value.pop_back();
  }
  const auto amount = std::stod(value);
  if (amount < 0) throw std::runtime_error(std::string{name} + " must not be negative");
  return std::chrono::milliseconds{static_cast<std::int64_t>(amount * multiplier)};
}

class StatusHandler final : public userver::server::handlers::HttpHandlerBase {
 public:
  static constexpr std::string_view kName = "native-status-handler";
  using HttpHandlerBase::HttpHandlerBase;

  std::string HandleRequest(userver::server::http::HttpRequest& request,
                            userver::server::request::RequestContext&) const override {
    request.GetHttpResponse().SetContentType(userver::http::content_type::kApplicationJson);
    return R"({"status":"ok"})";
  }
};

class MetricsHandler final : public userver::server::handlers::HttpHandlerBase {
 public:
  static constexpr std::string_view kName = "native-metrics-handler";
  using HttpHandlerBase::HttpHandlerBase;

  std::string HandleRequest(userver::server::http::HttpRequest&,
                            userver::server::request::RequestContext&) const override {
    return "# No ServiceLib runtime metrics in the native baseline.\n";
  }
};

}  // namespace native_example
