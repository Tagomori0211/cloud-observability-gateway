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

  Future<MetricsModel> fetchMetrics({bool bedrock = false}) async {
    final req = GetMetricsRequest()
      ..server = bedrock ? ServerType.BEDROCK : ServerType.JAVA;
    final res = await _client.getMetrics(req);
    return MetricsModel.fromProto(res);
  }

  Stream<MetricsModel> streamMetrics({bool bedrock = false}) {
    final req = GetMetricsRequest()
      ..server = bedrock ? ServerType.BEDROCK : ServerType.JAVA;
    return _client.streamMetrics(req).map(MetricsModel.fromProto);
  }
}
