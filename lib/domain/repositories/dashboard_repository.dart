import '../entities/dashboard_stats.dart';

abstract class DashboardRepository {
  Stream<DashboardStats> watchStats();
}
