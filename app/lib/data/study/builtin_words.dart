/// 内置词库：英语四级高频词（示例集，App 开箱即可背）。
///
/// 真实产品会按词库分级分批下发；这里内置一批足以跑通完整背词流程。
library;

class BuiltinWord {
  const BuiltinWord({
    required this.spelling,
    required this.meanings,
    this.phoneticUk,
    this.phoneticUs,
    this.example,
  });

  final String spelling;
  final List<String> meanings;
  final String? phoneticUk;
  final String? phoneticUs;
  final String? example;
}

const builtinWordbookName = 'CET-4 核心词';

const builtinCet4 = <BuiltinWord>[
  BuiltinWord(spelling: 'ability', phoneticUk: '/əˈbɪləti/', meanings: ['n. 能力，才能'], example: 'She has the ability to solve hard problems.'),
  BuiltinWord(spelling: 'absorb', phoneticUk: '/əbˈzɔːb/', meanings: ['v. 吸收；使专心'], example: 'Plants absorb water through their roots.'),
  BuiltinWord(spelling: 'achieve', phoneticUk: '/əˈtʃiːv/', meanings: ['v. 达到，实现'], example: 'He achieved his goal within a year.'),
  BuiltinWord(spelling: 'adapt', phoneticUk: '/əˈdæpt/', meanings: ['v. 适应；改编'], example: 'It takes time to adapt to a new city.'),
  BuiltinWord(spelling: 'advantage', phoneticUk: '/ədˈvɑːntɪdʒ/', meanings: ['n. 优势，好处'], example: 'Speaking English is a real advantage here.'),
  BuiltinWord(spelling: 'affect', phoneticUk: '/əˈfekt/', meanings: ['v. 影响，感动'], example: 'The weather affects my mood.'),
  BuiltinWord(spelling: 'afford', phoneticUk: '/əˈfɔːd/', meanings: ['v. 负担得起'], example: 'We cannot afford a bigger house.'),
  BuiltinWord(spelling: 'alternative', phoneticUk: '/ɔːlˈtɜːnətɪv/', meanings: ['n. 选择', 'a. 可替代的'], example: 'Is there an alternative plan?'),
  BuiltinWord(spelling: 'amount', phoneticUk: '/əˈmaʊnt/', meanings: ['n. 数量', 'v. 总计'], example: 'A large amount of data was lost.'),
  BuiltinWord(spelling: 'analyse', phoneticUk: '/ˈænəlaɪz/', phoneticUs: '/ˈænəlaɪz/', meanings: ['v. 分析'], example: 'Let us analyse the test results.'),
  BuiltinWord(spelling: 'annual', phoneticUk: '/ˈænjuəl/', meanings: ['a. 每年的', 'n. 年刊'], example: 'The annual meeting is in May.'),
  BuiltinWord(spelling: 'anxious', phoneticUk: '/ˈæŋkʃəs/', meanings: ['a. 焦虑的；急切的'], example: 'She was anxious about the interview.'),
  BuiltinWord(spelling: 'apologize', phoneticUk: '/əˈpɒlədʒaɪz/', meanings: ['v. 道歉'], example: 'You should apologize to her.'),
  BuiltinWord(spelling: 'apparent', phoneticUk: '/əˈpærənt/', meanings: ['a. 明显的'], example: 'It soon became apparent that he lied.'),
  BuiltinWord(spelling: 'appeal', phoneticUk: '/əˈpiːl/', meanings: ['v./n. 呼吁；吸引力'], example: 'The design appeals to young users.'),
  BuiltinWord(spelling: 'appreciate', phoneticUk: '/əˈpriːʃieɪt/', meanings: ['v. 感激；欣赏'], example: 'I appreciate your help.'),
  BuiltinWord(spelling: 'approach', phoneticUk: '/əˈprəʊtʃ/', meanings: ['v. 接近', 'n. 方法'], example: 'We need a new approach.'),
  BuiltinWord(spelling: 'appropriate', phoneticUk: '/əˈprəʊpriət/', meanings: ['a. 适当的'], example: 'Wear appropriate clothes for the weather.'),
  BuiltinWord(spelling: 'approve', phoneticUk: '/əˈpruːv/', meanings: ['v. 批准；赞成'], example: 'The manager approved the plan.'),
  BuiltinWord(spelling: 'arrange', phoneticUk: '/əˈreɪndʒ/', meanings: ['v. 安排；整理'], example: 'I will arrange a meeting tomorrow.'),
  BuiltinWord(spelling: 'artificial', phoneticUk: '/ˌɑːtɪˈfɪʃl/', meanings: ['a. 人造的；虚假的'], example: 'Artificial intelligence is changing work.'),
  BuiltinWord(spelling: 'assess', phoneticUk: '/əˈses/', meanings: ['v. 评估'], example: 'We assess risk before every release.'),
  BuiltinWord(spelling: 'assist', phoneticUk: '/əˈsɪst/', meanings: ['v. 帮助'], example: 'The tool assists users in writing.'),
  BuiltinWord(spelling: 'assume', phoneticUk: '/əˈsjuːm/', meanings: ['v. 假定；承担'], example: 'Do not assume everyone agrees.'),
  BuiltinWord(spelling: 'attach', phoneticUk: '/əˈtætʃ/', meanings: ['v. 附上；贴上'], example: 'Please attach the screenshot.'),
  BuiltinWord(spelling: 'attitude', phoneticUk: '/ˈætɪtjuːd/', meanings: ['n. 态度，看法'], example: 'His attitude changed after the talk.'),
  BuiltinWord(spelling: 'authority', phoneticUk: '/ɔːˈθɒrəti/', meanings: ['n. 权威；当局'], example: 'She is an authority on testing.'),
  BuiltinWord(spelling: 'available', phoneticUk: '/əˈveɪləbl/', meanings: ['a. 可用的；有空的'], example: 'The report is available online.'),
  BuiltinWord(spelling: 'avoid', phoneticUk: '/əˈvɔɪd/', meanings: ['v. 避免'], example: 'Avoid repeating the same mistake.'),
  BuiltinWord(spelling: 'aware', phoneticUk: '/əˈweə(r)/', meanings: ['a. 意识到的'], example: 'Are you aware of the deadline?'),
  BuiltinWord(spelling: 'balance', phoneticUk: '/ˈbæləns/', meanings: ['n. 平衡；余额', 'v. 使平衡'], example: 'Try to balance work and rest.'),
  BuiltinWord(spelling: 'benefit', phoneticUk: '/ˈbenɪfɪt/', meanings: ['n. 好处', 'v. 有益于'], example: 'Exercise benefits your heart.'),
  BuiltinWord(spelling: 'brief', phoneticUk: '/briːf/', meanings: ['a. 简短的', 'n. 摘要'], example: 'Give me a brief summary.'),
  BuiltinWord(spelling: 'budget', phoneticUk: '/ˈbʌdʒɪt/', meanings: ['n. 预算'], example: 'Set a monthly budget first.'),
  BuiltinWord(spelling: 'calculate', phoneticUk: '/ˈkælkjuleɪt/', meanings: ['v. 计算；估计'], example: 'Calculate the cost before buying.'),
  BuiltinWord(spelling: 'capable', phoneticUk: '/ˈkeɪpəbl/', meanings: ['a. 有能力的'], example: 'She is capable of leading the team.'),
  BuiltinWord(spelling: 'capacity', phoneticUk: '/kəˈpæsəti/', meanings: ['n. 容量；能力'], example: 'The hall has a capacity of 500.'),
  BuiltinWord(spelling: 'career', phoneticUk: '/kəˈrɪə(r)/', meanings: ['n. 职业，生涯'], example: 'He changed his career at 30.'),
  BuiltinWord(spelling: 'challenge', phoneticUk: '/ˈtʃælɪndʒ/', meanings: ['n. 挑战', 'v. 质疑'], example: 'Testing AI output is a real challenge.'),
  BuiltinWord(spelling: 'character', phoneticUk: '/ˈkærəktə(r)/', meanings: ['n. 性格；角色；字符'], example: 'The password needs special characters.'),
  BuiltinWord(spelling: 'citizen', phoneticUk: '/ˈsɪtɪzn/', meanings: ['n. 公民'], example: 'Every citizen has the right to vote.'),
  BuiltinWord(spelling: 'claim', phoneticUk: '/kleɪm/', meanings: ['v. 声称；索取', 'n. 主张'], example: 'He claims the file was deleted.'),
  BuiltinWord(spelling: 'classify', phoneticUk: '/ˈklæsɪfaɪ/', meanings: ['v. 分类'], example: 'Classify the defects by severity.'),
  BuiltinWord(spelling: 'comfort', phoneticUk: '/ˈkʌmfət/', meanings: ['n. 舒适；安慰', 'v. 安慰'], example: 'The shoes are built for comfort.'),
  BuiltinWord(spelling: 'community', phoneticUk: '/kəˈmjuːnəti/', meanings: ['n. 社区；群体'], example: 'The open source community is helpful.'),
  BuiltinWord(spelling: 'compare', phoneticUk: '/kəmˈpeə(r)/', meanings: ['v. 比较'], example: 'Compare the two designs carefully.'),
  BuiltinWord(spelling: 'complex', phoneticUk: '/ˈkɒmpleks/', meanings: ['a. 复杂的', 'n. 综合体'], example: 'The logic is more complex than it looks.'),
  BuiltinWord(spelling: 'conclude', phoneticUk: '/kənˈkluːd/', meanings: ['v. 得出结论；结束'], example: 'We conclude that the bug is fixed.'),
  BuiltinWord(spelling: 'confident', phoneticUk: '/ˈkɒnfɪdənt/', meanings: ['a. 自信的'], example: 'Be confident in your own judgement.'),
  BuiltinWord(spelling: 'consider', phoneticUk: '/kənˈsɪdə(r)/', meanings: ['v. 考虑；认为'], example: 'Consider the cost before you start.'),
];
