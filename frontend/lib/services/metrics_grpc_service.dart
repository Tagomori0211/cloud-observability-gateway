import 'package:grpc/grpc_web.dart';
import '../src/generated/shared.pb.dart';
import '../src/generated/shared.pbgrpc.dart';
import '../models/metrics_model.dart';

class MetricsGrpcService {
  late final MetricsServiceClient _client;

  MetricsGrpcService() {
    final channel = GrpcWebClientChannel.xhr(Uri.base);
    _client = MetricsServiceClient(channel);
  }

  Future<MetricsModel> fetchMetrics() async {
    final res = await _client.getMetrics(GetMetricsRequest());
    return MetricsModel.fromProto(res);
  }

  Stream<MetricsModel> streamMetrics() {
    return _client
        .streamMetrics(GetMetricsRequest())
        .map(MetricsModel.fromProto);
  }
}
