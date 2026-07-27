import 'package:data/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the three authoritative required-credit values from home', () {
    const html = '''
      <section class="study-progress">
        <div><span>应修必修</span><span>49%</span><strong>157.5分</strong></div>
        <div><span>应修选修</span><span>45%</span><strong>15.5分</strong></div>
        <div><span>应修校选</span><span>67%</span><strong>3分</strong></div>
      </section>
    ''';

    expect(StudyProgressDashboardParser.parseRequiredCredits(html), const {
      'compulsory': 157.5,
      'elective': 15.5,
      'schoolElective': 3.0,
    });
  });

  test('returns no override when the academic-home ledger is absent', () {
    expect(
      StudyProgressDashboardParser.parseRequiredCredits('<main>我的课表</main>'),
      isEmpty,
    );
  });

  test('does not use a later earned-credit value for school-elective need', () {
    const html = '''
      <main>
        <section class="required-credit-card">
          <div><span>应修必修</span><strong>157.5分</strong></div>
          <div><span>应修选修</span><strong>15.5分</strong></div>
          <div><span>应修校选</span><strong>3分</strong></div>
        </section>
        <section class="earned-credit-card">已修校选 150分</section>
      </main>
    ''';

    expect(
      StudyProgressDashboardParser.parseRequiredCredits(html)['schoolElective'],
      3,
    );
  });
}
