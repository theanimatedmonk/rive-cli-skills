// The 22 Major Arcana. `image` is the card face: it is decoded and bound to
// the Rive view model's `face` image, and shown on the final screen.
// `career`, `love` and `finance` are the upright readings shown on the
// final screen's orbit, one per planet.
// Card art: Rider–Waite–Smith (1909), public domain, via Wikimedia Commons.
const TAROT_PERSONAS = [
  {
    image: "assets/cards/00-fool.jpg",
    name: "The Fool",
    career:
      "A fresh start is calling: a new role, a side project or a complete change of direction. Say yes before you feel fully ready. Curiosity will teach you faster than caution.",
    love:
      "Approach love with an open, playful heart. Single, you may meet someone unexpected; together, try something new side by side. Let go of old stories about how love should look.",
    finance:
      "Exciting opportunities may tempt you, so enjoy the adventure but keep a safety net. Spontaneous spending can feel freeing. Make sure you can afford the leap before you take it.",
  },
  {
    image: "assets/cards/01-magician.jpg",
    name: "The Magician",
    career:
      "You have every skill and tool you need to make your plans real. Pitch the idea, lead the meeting, launch the project. Focused action now turns potential into results.",
    love:
      "Your charm and confidence are magnetic. Say clearly what you want, because honest words create real connection. A relationship can grow quickly when both of you show up with intention.",
    finance:
      "Resourcefulness pays off: a smart idea or a new skill can open a fresh income stream. Plan carefully and act decisively. Money follows clear purpose.",
  },
  {
    image: "assets/cards/02-high-priestess.jpg",
    name: "The High Priestess",
    career:
      "Not everything at work is out in the open yet. Watch quietly, listen more than you speak and trust your read of people. Your intuition will guide the right decision.",
    love:
      "Deep feelings may stay unspoken for now. Give connections time to reveal themselves rather than forcing answers. Trust what your heart already senses.",
    finance:
      "Keep financial plans private and avoid rushing into deals you don't fully understand. Do your research quietly. Your gut will warn you about anything that doesn't add up.",
  },
  {
    image: "assets/cards/03-empress.jpg",
    name: "The Empress",
    career:
      "Creative work flourishes now. Projects you have nurtured patiently begin to grow and attract recognition. Bring warmth and care to your team and they will thrive with you.",
    love:
      "Love feels abundant, sensual and nurturing. Relationships deepen through comfort, affection and shared pleasures. It's a beautiful time to build a home or a family together.",
    finance:
      "Abundance is within reach as earlier efforts start bearing fruit. Enjoy life's comforts, and keep investing in things that grow. Patience brings a generous harvest.",
  },
  {
    image: "assets/cards/04-emperor.jpg",
    name: "The Emperor",
    career:
      "Leadership is your path now. Discipline, planning and steady effort can bring a promotion or real authority. Take charge and set the structure others will follow.",
    love:
      "You love in a serious, protective and sincere way. Stability and loyalty matter more than grand gestures. Traditional commitment, like marriage or shared long-term goals, feels right.",
    finance:
      "A great moment to make your finances stable and secure. Set a clear budget and stick to it. Rein in impulsive spending and your position will steadily strengthen.",
  },
  {
    image: "assets/cards/05-hierophant.jpg",
    name: "The Hierophant",
    career:
      "Growth comes through learning, mentors and established paths. A course, a qualification or a trusted guide will move you forward. Respect proven methods while you build your expertise.",
    love:
      "Shared values and commitment are at the heart of love now. Traditional milestones like engagement or marriage may be on your mind. Seek a partner whose beliefs sit in harmony with yours.",
    finance:
      "Play it safe with conventional, reliable choices. Seek advice from a trusted expert before big decisions. Steady, rule-following habits protect your money best.",
  },
  {
    image: "assets/cards/06-lovers.jpg",
    name: "The Lovers",
    career:
      "An important choice is coming, so pick the path that matches your values, not just your ambitions. Partnerships and collaboration are especially powerful now. Work you believe in brings the best results.",
    love:
      "Deep connection, attraction and harmony are highlighted. A relationship may reach a meaningful new level. Choose love with both your heart and your values.",
    finance:
      "Financial decisions work best when made together and aligned with what truly matters to you. Weigh options honestly. Avoid spending to impress, and spend on what you love.",
  },
  {
    image: "assets/cards/07-chariot.jpg",
    name: "The Chariot",
    career:
      "Determination drives you forward. Focus your energy on one clear goal and push through obstacles. Victory comes from discipline, confidence and refusing to give up.",
    love:
      "Take the reins in matters of the heart: pursue what you want with confidence. Couples can overcome challenges by pulling in the same direction. Balance passion with self-control.",
    finance:
      "Steady control over your money leads to progress. Set ambitious targets and stay disciplined to reach them. A determined push now can clear debts or build real savings.",
  },
  {
    image: "assets/cards/08-strength.jpg",
    name: "Strength",
    career:
      "Quiet confidence and patience win the day. Handle difficult people or pressure with calm compassion rather than force. Your inner resilience earns lasting respect.",
    love:
      "Gentleness and patience strengthen your bond. Face tensions with kindness and understanding instead of pride. Love grows when you lead with an open heart.",
    finance:
      "Self-discipline is your greatest financial asset now. Resist temptation and stay calm through any money worries. Steady courage carries you through tight moments.",
  },
  {
    image: "assets/cards/09-hermit.jpg",
    name: "The Hermit",
    career:
      "Step back and reflect on what you truly want from your work. Solo focus, research or deep study suits you now. The answers come from within, not from the crowd.",
    love:
      "You may need time alone to understand your own heart. Single, use this time for self-discovery; together, give each other space. Clarity leads to deeper connection later.",
    finance:
      "A thoughtful, conservative approach serves you well. Review your finances in detail and cut what no longer serves you. Wisdom matters more than quick wins now.",
  },
  {
    image: "assets/cards/10-wheel-of-fortune.jpg",
    name: "Wheel of Fortune",
    career:
      "The wheel is turning in your favor. Unexpected opportunities or changes can shift your career quickly. Stay adaptable and seize lucky breaks when they appear.",
    love:
      "Fate may play a hand in love, through a chance meeting or a turning point in a relationship. Embrace the changes life brings. What is meant for you will find its way.",
    finance:
      "Fortunes can change suddenly, often for the better. Enjoy good luck but remember cycles turn. Save some of today's gains for the seasons ahead.",
  },
  {
    image: "assets/cards/11-justice.jpg",
    name: "Justice",
    career:
      "Fairness and integrity guide your path. Contracts, negotiations or legal matters resolve in your favor if you act honestly. Your hard work is weighed and rewarded fairly.",
    love:
      "Balance and honesty are essential in love now. Relationships thrive when both partners give equally. Truthful conversations restore harmony.",
    finance:
      "Financial matters come into balance. Settle debts, read the fine print and make decisions based on facts. Fair dealings bring fair returns.",
  },
  {
    image: "assets/cards/12-hanged-man.jpg",
    name: "The Hanged Man",
    career:
      "Progress may feel paused, but this pause has purpose. Look at your situation from a new angle before acting. A shift in perspective reveals a better way forward.",
    love:
      "Let go of control and see your relationship through fresh eyes. Patience and surrender can soften old tensions. Sometimes waiting is the most loving choice.",
    finance:
      "Hold off on major financial moves for now. Reassess priorities and let situations unfold. A short-term sacrifice can lead to long-term gain.",
  },
  {
    image: "assets/cards/13-death.jpg",
    name: "Death",
    career:
      "One chapter of your career is closing so another can begin. Let go of roles or projects that no longer fit. Transformation clears the way for meaningful growth.",
    love:
      "Old patterns in love are ending, making room for renewal. A relationship may transform deeply or come to a natural close. Embrace change as a fresh beginning.",
    finance:
      "Release outdated money habits and start fresh. Endings, like closing an account or changing income, can open better paths. Transformation leads to a healthier foundation.",
  },
  {
    image: "assets/cards/14-temperance.jpg",
    name: "Temperance",
    career:
      "Balance and patience lead to steady success. Blend skills, collaborate and avoid extremes. A calm, measured approach builds lasting results.",
    love:
      "Harmony and compromise make love flourish. Meet your partner halfway and find a gentle rhythm together. Healing and patience bring you closer.",
    finance:
      "Moderation is key: balance saving and spending wisely. Avoid risky extremes and make steady, thoughtful choices. Slow, consistent progress builds security.",
  },
  {
    image: "assets/cards/15-devil.jpg",
    name: "The Devil",
    career:
      "Notice where you feel trapped, by a job, a habit or someone else's expectations. Recognising the chains is the first step to breaking free. You have more choices than you think.",
    love:
      "Passion runs high, but watch for jealousy, dependence or unhealthy patterns. Choose connection that frees you rather than binds you. Honest boundaries protect your heart.",
    finance:
      "Be wary of overspending, debt or get-rich-quick temptations. Material desires may cloud your judgment. Regain control by facing your money habits honestly.",
  },
  {
    image: "assets/cards/16-tower.jpg",
    name: "The Tower",
    career:
      "Sudden change may shake your work life. What falls apart was built on shaky ground. Rebuild with honesty and stronger foundations.",
    love:
      "Revelations may disrupt a relationship or reveal hidden truths. Though unsettling, this upheaval clears the way for authenticity. Build love on honesty from here on.",
    finance:
      "Prepare for unexpected expenses or shifts in income. Keep an emergency fund close. Recovery comes from facing reality and rebuilding wisely.",
  },
  {
    image: "assets/cards/17-star.jpg",
    name: "The Star",
    career:
      "Hope and inspiration return to your work. Pursue goals that feel meaningful and let your talents shine. Recognition and renewed purpose are on the horizon.",
    love:
      "Love feels hopeful, healing and sincere. Old wounds begin to mend and trust grows. Open your heart; the universe is supporting you.",
    finance:
      "After difficult times, your finances begin to recover. Stay optimistic and keep making steady, positive choices. Generosity and gratitude attract more abundance.",
  },
  {
    image: "assets/cards/18-moon.jpg",
    name: "The Moon",
    career:
      "Things at work may not be what they seem. Read between the lines and avoid hasty decisions. Trust your instincts while uncertainty settles.",
    love:
      "Emotions run deep but may feel confusing. Avoid assumptions and talk openly about fears or doubts. Clarity comes once the fog lifts.",
    finance:
      "Be cautious with unclear deals, hidden costs or misleading offers. Double-check details before committing. Patience protects you from costly mistakes.",
  },
  {
    image: "assets/cards/19-sun.jpg",
    name: "The Sun",
    career:
      "Success and recognition shine on your work. Projects flourish and your confidence inspires others. Celebrate the achievements you have earned.",
    love:
      "Joy, warmth and happiness fill your love life. Relationships feel light, honest and full of fun. Share your happiness openly.",
    finance:
      "Prosperity and stability brighten your finances. Investments and efforts pay off generously. Enjoy the rewards and share your good fortune.",
  },
  {
    image: "assets/cards/20-judgement.jpg",
    name: "Judgement",
    career:
      "A calling or important evaluation arrives. Reflect on your journey and answer the opportunity with confidence. This is a moment of awakening and new direction.",
    love:
      "Look honestly at your relationship and what it truly needs. Forgiveness and renewal can bring you closer. A meaningful second chance may appear.",
    finance:
      "Review past financial decisions and learn from them. A clear assessment leads to wiser choices. Old matters may finally resolve.",
  },
  {
    image: "assets/cards/21-world.jpg",
    name: "The World",
    career:
      "A major goal is achieved and a cycle completes. Recognition, travel or expansion may follow. Celebrate your success before reaching for the next horizon.",
    love:
      "Love feels whole, fulfilled and complete. A relationship may reach a significant milestone. Enjoy the deep harmony you have built together.",
    finance:
      "Financial goals are reached and stability feels secure. Celebrate your accomplishments wisely. A new chapter of opportunity begins.",
  },
];
