// The 22 Major Arcana. `image` is the card face: it is decoded and bound to
// the Rive view model's `face` image, and shown on the final screen.
// `career`, `love` and `finance` are the upright readings shown on the
// final screen, one per topic. Each runs 400–600 characters, as long as
// the readings the API returns, so the layouts are tested with real lengths.
// Card art: Rider–Waite–Smith (1909), public domain, via Wikimedia Commons.
const TAROT_PERSONAS = [
  {
    image: "assets/cards/00-fool.jpg",
    name: "The Fool",
    career:
      "When it comes to Career, The Fool signals a fresh start that is calling you forward: a new role, a side project or a complete change of direction. You may not feel fully ready, and that is exactly the point, because this card rewards those who say yes before every detail is settled. Curiosity will teach you faster than caution right now. Trust your instincts, stay open to learning on the job, and let the excitement of beginning something new carry you through the early uncertainty.",
    love:
      "In love, The Fool asks you to approach matters of the heart with an open, playful spirit. If you are single, someone unexpected may cross your path, perhaps in a place or way you would never have planned. If you are in a relationship, this is a wonderful time to try something new together, whether a trip, a hobby or simply a change of routine. Let go of old stories about how love is supposed to look, and allow yourself to be surprised by what unfolds when you stop overthinking and simply enjoy the moment.",
    finance:
      "Financially, The Fool brings exciting opportunities that may tempt you to leap without looking. Enjoy the sense of adventure, but keep a safety net in place before you commit. Spontaneous spending can feel freeing in the moment, yet it can quietly undo the progress you have made. Before any big move, ask yourself whether you could afford the loss if things went differently. A little planning now lets you take the leap with confidence rather than worry.",
  },
  {
    image: "assets/cards/01-magician.jpg",
    name: "The Magician",
    career:
      "When it comes to Career, The Magician shows that you already have every skill, tool and contact you need to turn your plans into reality. This is the moment to pitch the idea, lead the meeting or launch the project you have been preparing. Others will notice your focus and your ability to make things happen. The key is concentrated action: choose one clear goal and pour your energy into it, and you will see potential transform into tangible, visible results.",
    love:
      "In love, The Magician makes your charm and confidence especially magnetic. People are drawn to your energy, and you have the power to create the connection you want. Say clearly what you are looking for, because honest and intentional words build real intimacy now. For couples, this card encourages both partners to show up with purpose and effort. A relationship can grow quickly when you communicate openly and act on your feelings rather than waiting for the other person to make the first move.",
    finance:
      "Financially, The Magician rewards resourcefulness. A smart idea, a new skill or an overlooked talent could open a fresh income stream for you. Look at what you already have and ask how it could be put to better use. Plan carefully, then act decisively once you see the opportunity. Money tends to follow clear purpose under this card, so set a specific goal and direct your efforts towards it instead of spreading yourself across too many projects at once.",
  },
  {
    image: "assets/cards/02-high-priestess.jpg",
    name: "The High Priestess",
    career:
      "When it comes to Career, The High Priestess suggests that not everything at work is out in the open yet. There may be plans, politics or decisions happening behind the scenes. This is a time to watch quietly, listen more than you speak, and trust your read of people and situations. Avoid revealing your hand too early. Your intuition is unusually sharp right now, and if something feels off, it probably is. Let that inner knowing guide your next decision rather than the loudest voice in the room.",
    love:
      "In love, The High Priestess points to deep feelings that may stay unspoken for now. There could be an attraction that has not yet been expressed, or emotions in a relationship that need time to surface. Rather than forcing answers or demanding clarity, give the connection space to reveal itself naturally. Pay attention to small signals, silences and gestures, as they say more than words. Trust what your heart already senses, because your intuition about this person and this situation is likely to be accurate.",
    finance:
      "Financially, The High Priestess advises discretion. Keep your financial plans private and avoid rushing into deals or investments you do not fully understand. Do your research quietly and take time to read the details others might skip. If an offer seems too good to be true or someone is pressuring you to decide quickly, step back. Your gut will warn you about anything that does not add up, so trust that feeling and wait until the picture is clear.",
  },
  {
    image: "assets/cards/03-empress.jpg",
    name: "The Empress",
    career:
      "When it comes to Career, The Empress brings a season of creative growth. Projects you have nurtured patiently are beginning to flourish and attract recognition. This is an excellent time for work involving design, care, teaching or anything that brings beauty and comfort to others. Bring warmth and generosity to your team, and you will find that people thrive around you. Success under this card comes not from force but from steady nurturing, so keep tending to your ideas and watch them grow.",
    love:
      "In love, The Empress makes this a time of abundance, sensuality and deep nurturing. Relationships grow stronger through comfort, affection and shared pleasures such as good food, time in nature or simply being close. If you are in a partnership, this is a beautiful period to build a home or talk about family together. If you are single, focus on loving and caring for yourself, as that warmth will naturally draw the right person towards you. Let yourself both give and receive tenderness freely.",
    finance:
      "Financially, The Empress shows that abundance is within reach as earlier efforts start to bear fruit. You may notice money coming in more easily or investments beginning to grow. Enjoy life's comforts, because you have earned them, but keep putting resources into things that will continue to grow over time. Patience is your greatest ally here. Like a well-tended garden, your finances will reward consistent care with a generous harvest, so avoid uprooting good plans too early.",
  },
  {
    image: "assets/cards/04-emperor.jpg",
    name: "The Emperor",
    career:
      "When it comes to Career, The Emperor leads you towards leadership goals that reward your hard work. As your career progresses, you are likely to receive a major promotion or step into a role with real authority, marking a high point in your professional journey. You will achieve the best results by turning these opportunities into reality through discipline and careful planning. Take charge, set clear expectations, and build the structure others will follow, both in your career and in your personal life.",
    love:
      "In love, The Emperor brings a serious, protective and sincere energy. Rather than chasing excitement, this card values discipline, logic and building something stable that lasts. Whether it appears for a man or a woman, it describes a steady person who knows their goals and pursues them with confidence. In a relationship, this leads to sincerity and a partnership that works in harmony, free of selfish motives. Traditional commitment, such as marriage or shared long-term goals, feels natural and right under this card.",
    finance:
      "Financially, The Emperor marks an excellent time to act on the plans you have been pursuing to secure your future. The main weakness to watch is spending habits, which may need tightening if you want your financial position to keep improving. Otherwise, you have a clear understanding of your money and the focus to set a budget and stick to it. Build structure into your finances, rein in impulsive purchases, and your stability will steadily strengthen over the coming months.",
  },
  {
    image: "assets/cards/05-hierophant.jpg",
    name: "The Hierophant",
    career:
      "When it comes to Career, The Hierophant shows that growth comes through learning, mentors and established paths. A course, a qualification or guidance from someone more experienced will move you forward faster than going it alone. This is not the moment to break every rule; instead, respect proven methods while you build your expertise. Working within a respected institution or tradition could bring stability and recognition. Seek out a teacher, absorb what they know, and you will soon be ready to lead in your own right.",
    love:
      "In love, The Hierophant places shared values and commitment at the heart of your relationships. Traditional milestones such as engagement, marriage or meeting each other's families may be on your mind. This card favours partners who share your beliefs and want the same things from life. If you are single, you may meet someone through family, community or a familiar setting. Seek a partner whose principles sit in harmony with yours, as that common ground will become the foundation of a lasting bond.",
    finance:
      "Financially, The Hierophant advises you to play it safe with conventional, reliable choices. This is not the time for risky ventures or untested schemes. Before making big decisions, seek advice from a trusted expert such as a financial adviser, an accountant or an experienced family member. Long-established institutions and steady savings plans work in your favour now. Following the rules and sticking to sensible, time-tested habits will protect your money and help it grow gradually.",
  },
  {
    image: "assets/cards/06-lovers.jpg",
    name: "The Lovers",
    career:
      "When it comes to Career, The Lovers signals that an important choice is approaching. You may be weighing two roles, two paths or two very different visions for your future. Choose the option that matches your values, not just your ambitions or the salary on offer. Partnerships and collaboration are especially powerful now, and working closely with the right person could change everything. Work you truly believe in will bring the best results and the deepest satisfaction over the long run.",
    love:
      "In love, The Lovers highlights deep connection, attraction and harmony. This is one of the most romantic cards in the deck, and it often shows a relationship reaching a meaningful new level of intimacy or commitment. You may feel a powerful bond with someone that goes beyond the physical. At the same time, the card reminds you that love is a choice. Choose with both your heart and your values, making sure the person beside you supports who you truly are and who you want to become.",
    finance:
      "Financially, The Lovers suggests that decisions work best when made together and aligned with what truly matters to you. If you share finances with a partner, talk openly about goals and priorities before committing to anything large. Weigh your options honestly rather than following impulse. Avoid spending to impress others or keep up appearances. Instead, put your money towards the people, experiences and things you genuinely love, and you will feel far richer for it.",
  },
  {
    image: "assets/cards/07-chariot.jpg",
    name: "The Chariot",
    career:
      "When it comes to Career, The Chariot shows determination driving you forward. You have the willpower to overcome obstacles that might stop others, as long as you stay focused on one clear goal. Scattered effort will slow you down, so decide where you are heading and commit fully. Competition may be strong, but your discipline and confidence give you the edge. Victory comes to those who refuse to give up, and this card promises that steady, directed effort will carry you to success.",
    love:
      "In love, The Chariot encourages you to take the reins in matters of the heart. If there is someone you want, pursue them with confidence instead of waiting for fate to step in. For couples, this card shows that challenges can be overcome when both partners pull in the same direction. Differences in temperament may need careful handling. Balance passion with self-control, and make sure you are steering the relationship together rather than competing to lead it.",
    finance:
      "Financially, The Chariot brings progress through steady control of your money. Set ambitious targets, whether paying off debt, saving for a major purchase or growing an investment, and stay disciplined in reaching them. Distractions and tempting purchases will test your resolve, but your determination is strong right now. A focused push over the coming weeks can clear old debts or build real savings. Keep your eyes on the goal, and you will be surprised how far you travel.",
  },
  {
    image: "assets/cards/08-strength.jpg",
    name: "Strength",
    career:
      "When it comes to Career, Strength shows that quiet confidence and patience will win the day. You may be dealing with difficult colleagues, demanding clients or heavy pressure, and the answer is calm compassion rather than force. People will respond better to your steadiness than to any show of power. Your inner resilience is greater than you realise, and the way you handle challenges now will earn lasting respect. Keep your temper, trust your abilities, and let your composure speak for itself.",
    love:
      "In love, Strength shows that gentleness and patience will deepen your bond. Tensions or misunderstandings are best faced with kindness and understanding instead of pride or stubbornness. This card reminds you that real strength in a relationship means being soft when it matters, listening fully and forgiving small hurts. If you are single, have the courage to be open and vulnerable. Love grows when you lead with an open heart, and the warmth you offer will be returned to you.",
    finance:
      "Financially, Strength makes self-discipline your greatest asset. Temptations to overspend or make emotional purchases may appear, but you have the inner control to resist them. If money worries are weighing on you, stay calm and deal with them one step at a time rather than panicking. Your steady courage will carry you through tight moments. Small, consistent choices made with patience will gradually build a stronger and more secure position than any dramatic gesture could.",
  },
  {
    image: "assets/cards/09-hermit.jpg",
    name: "The Hermit",
    career:
      "When it comes to Career, The Hermit invites you to step back and reflect on what you truly want from your work. The noise of other people's opinions may be drowning out your own sense of direction. Solo focus, research, writing or deep study suit you particularly well now. You may prefer working independently for a while, and that is perfectly fine. The answers you are looking for will come from within rather than from the crowd, so give yourself the quiet you need to hear them.",
    love:
      "In love, The Hermit suggests you may need time alone to understand your own heart. If you are single, use this period for self-discovery rather than rushing into something new. If you are in a relationship, give each other some breathing space and respect the need for solitude without taking it personally. This is not a sign of distance but of growth. The clarity you gain now will lead to a deeper, more honest connection later, once you know exactly what you are looking for.",
    finance:
      "Financially, The Hermit favours a thoughtful and conservative approach. Take time to review your finances in detail, examining where your money goes and whether each expense still serves you. Cut back on what no longer adds value to your life. This is not a time for flashy purchases or following trends. Quiet wisdom matters more than quick wins, and a careful, well-considered plan made in calm reflection will protect and strengthen your position for a long time to come.",
  },
  {
    image: "assets/cards/10-wheel-of-fortune.jpg",
    name: "Wheel of Fortune",
    career:
      "When it comes to Career, the Wheel of Fortune shows that the wheel is turning in your favour. Unexpected opportunities, sudden changes or lucky introductions could shift your career more quickly than you expect. A project may take off, a new door may open, or the right person may notice your work at just the right time. Stay adaptable and ready to move. Seize these lucky breaks when they appear, because timing is everything under this card, and hesitation could let the moment pass.",
    love:
      "In love, the Wheel of Fortune suggests that fate may play a hand. A chance meeting could turn into something meaningful, or a relationship could reach an important turning point. Changes may arrive suddenly, and while some may feel unsettling, they are moving you towards where you are meant to be. Embrace what life brings instead of clinging to how things used to be. What is truly meant for you will find its way, so stay open and trust the timing of your heart.",
    finance:
      "Financially, the Wheel of Fortune indicates that fortunes can change suddenly, and often for the better. You may receive an unexpected bonus, a windfall or a profitable opportunity. Enjoy the good luck, but remember that the wheel always keeps turning, and cycles of plenty are followed by quieter times. Set aside some of today's gains for the seasons ahead. Using good fortune wisely now will make sure you stay comfortable when the wheel eventually moves on.",
  },
  {
    image: "assets/cards/11-justice.jpg",
    name: "Justice",
    career:
      "When it comes to Career, Justice shows that fairness and integrity will guide your path. Contracts, negotiations, reviews or legal matters are likely to resolve in your favour, as long as you act honestly and keep good records. Your hard work is being weighed carefully, and it will be rewarded fairly. This is a good time to ask for what you deserve, backed by clear evidence of your contributions. Make decisions based on facts rather than emotion, and the outcome will reflect your effort.",
    love:
      "In love, Justice makes balance and honesty essential. Relationships thrive when both partners give equally, and any imbalance in effort or care will become hard to ignore. This may be a time for truthful conversations about what each of you needs. Though such talks can feel difficult, they restore harmony and fairness. If you are single, you may attract someone whose values match yours. Treat others as you wish to be treated, and the love you receive will mirror what you give.",
    finance:
      "Financially, Justice brings your money matters into balance. This is an ideal time to settle debts, resolve disputes and tie up loose ends. Read the fine print carefully before signing anything, and base your decisions on facts rather than hopes. Legal or official matters relating to money are likely to be resolved fairly. Fair dealings bring fair returns under this card, so stay honest in every transaction and you will find your finances becoming steadier and clearer.",
  },
  {
    image: "assets/cards/12-hanged-man.jpg",
    name: "The Hanged Man",
    career:
      "When it comes to Career, The Hanged Man suggests that progress may feel paused, but this pause has a purpose. Projects may stall or decisions may be delayed by forces beyond your control. Rather than pushing harder, use this time to look at your situation from a completely new angle. What seems like a setback could reveal a better path that you would never have noticed while rushing. A shift in perspective now will help you move forward with far more clarity once things start moving again.",
    love:
      "In love, The Hanged Man asks you to let go of control and see your relationship through fresh eyes. You may be waiting for someone to decide, or a relationship may feel suspended between stages. Instead of forcing an outcome, practise patience and surrender. This gentle approach can soften old tensions and reveal what really matters to both of you. Sometimes waiting is the most loving choice, and the understanding you gain during this pause can transform how you connect.",
    finance:
      "Financially, The Hanged Man advises holding off on major moves for now. This is not the right moment to make large investments, sign big contracts or change direction abruptly. Instead, step back and reassess your priorities, letting situations unfold before you act. You may be asked to make a short-term sacrifice, such as delaying a purchase or saving instead of spending. That sacrifice is likely to lead to a long-term gain, so trust the pause and use it to plan wisely.",
  },
  {
    image: "assets/cards/13-death.jpg",
    name: "Death",
    career:
      "When it comes to Career, Death shows one chapter of your working life closing so another can begin. A role, project or way of working may be coming to an end, and resisting it will only prolong the discomfort. Let go of what no longer fits who you are becoming. This card rarely means literal loss; it means transformation. By clearing away the old, you create room for meaningful growth, new skills and a direction that feels far more aligned with your goals.",
    love:
      "In love, Death signals that old patterns are ending to make room for renewal. A relationship may go through a deep transformation, emerging stronger and more honest, or it may come to a natural and necessary close. Either way, this change is not something to fear. It is clearing space for a healthier way of loving. If you are single, let go of past heartbreak and old expectations. Embrace this change as a fresh beginning, and you will open the door to something new.",
    finance:
      "Financially, Death asks you to release outdated money habits and start fresh. An ending, such as closing an account, leaving a job or changing your source of income, may feel unsettling at first but can open better paths. Look honestly at which financial patterns have been holding you back and be willing to let them go. This transformation lays the groundwork for a healthier foundation. What you rebuild now will be stronger and better suited to the life you want.",
  },
  {
    image: "assets/cards/14-temperance.jpg",
    name: "Temperance",
    career:
      "When it comes to Career, Temperance shows that balance and patience will lead to steady success. Blending different skills, ideas or people together could produce something better than any single approach. Avoid extremes such as overworking or cutting corners. A calm, measured pace lets you build results that last. You may find yourself acting as a mediator or bridge between colleagues. Your ability to find the middle ground is a real strength now, and it will earn you trust and respect.",
    love:
      "In love, Temperance makes harmony and compromise the keys to a flourishing relationship. Meet your partner halfway, and look for a gentle rhythm that suits you both rather than insisting on your own way. This card is also about healing, so old wounds can begin to mend with patience and care. If you are single, balance your own needs with openness to others. Love grows slowly but beautifully under this card, and the bond you build now will be calm, steady and deeply nourishing.",
    finance:
      "Financially, Temperance makes moderation the key to success. Aim for a healthy balance between saving and spending, so that you enjoy life without putting your future at risk. Avoid risky extremes such as reckless investments or harsh restrictions that make you miserable. Instead, make steady, thoughtful choices and review them regularly. Slow and consistent progress may not feel exciting, but it builds the kind of financial security that lasts and gives you real peace of mind.",
  },
  {
    image: "assets/cards/15-devil.jpg",
    name: "The Devil",
    career:
      "When it comes to Career, The Devil asks you to notice where you feel trapped, whether by a job, a habit or someone else's expectations. You may be staying in a role out of fear, comfort or pressure rather than real choice. Recognising these chains is the first step to breaking free. Be honest about what is keeping you stuck, including any unhealthy work habits such as burnout or people-pleasing. You have far more options than you think, and taking back control begins with admitting you want something different.",
    love:
      "In love, The Devil brings intense passion and attraction, but also a warning. Watch for jealousy, possessiveness, dependence or patterns that feel exciting yet leave you drained. A relationship based mainly on desire or habit may not be serving your wellbeing. Choose connection that frees you rather than binds you. Honest boundaries protect your heart, and talking openly about difficult dynamics can turn an unhealthy cycle into a healthier, more balanced partnership.",
    finance:
      "Financially, The Devil cautions against overspending, mounting debt and get-rich-quick temptations. Material desires may be clouding your judgment, leading you to buy things you do not need or take risks you cannot afford. Look honestly at your money habits, especially those driven by stress or impulse. Regaining control starts with facing the numbers directly. Once you do, you will discover that you have more power to change your situation than you previously believed.",
  },
  {
    image: "assets/cards/16-tower.jpg",
    name: "The Tower",
    career:
      "When it comes to Career, The Tower warns that sudden change may shake your working life. A restructure, an unexpected decision or a surprising revelation could disrupt plans you thought were secure. While this may feel alarming, what falls apart was likely built on shaky ground to begin with. This upheaval clears the way for something more honest and stable. Stay calm, focus on what you can control, and rebuild with stronger foundations that truly reflect your skills and values.",
    love:
      "In love, The Tower suggests that revelations may disrupt a relationship or bring hidden truths into the open. An unexpected conversation or event could change how you see someone, or how they see you. Though unsettling, this shake-up clears away illusions and makes room for authenticity. Relationships that survive it can emerge stronger and more honest. From here on, build love on openness and truth, because foundations based on pretence will not hold for long.",
    finance:
      "Financially, The Tower advises you to prepare for unexpected expenses or sudden shifts in income. A repair, a lost contract or an unplanned cost could test your resources. Keeping an emergency fund close will soften the impact considerably. If something does go wrong, resist the urge to panic. Recovery comes from facing reality quickly and rebuilding wisely. The lessons learned from this disruption will help you create a far more resilient financial structure going forward.",
  },
  {
    image: "assets/cards/17-star.jpg",
    name: "The Star",
    career:
      "When it comes to Career, The Star brings hope and inspiration back to your work. After a challenging period, you may feel renewed purpose and a clearer sense of what you want to achieve. Pursue goals that feel genuinely meaningful to you, and let your unique talents shine. Creative, healing and visionary work is especially favoured. Recognition and fresh opportunities are on the horizon, and the faith you place in yourself now will guide you towards a future that feels bright.",
    love:
      "In love, The Star makes this a hopeful, healing and sincere time. Old wounds begin to mend, and trust slowly grows again where it had been damaged. If you are single, you may feel ready to open your heart after a period of recovery. If you are in a relationship, expect a renewed sense of peace and closeness. This card encourages vulnerability and honesty. Open your heart without fear, because the universe is supporting you and gentle, lasting love is within reach.",
    finance:
      "Financially, The Star shows your finances beginning to recover after difficult times. Things may not change overnight, but the trend is moving firmly in a positive direction. Stay optimistic and keep making steady, sensible choices. This is a good time to set long-term goals and dream a little about what you want your future to look like. Generosity and gratitude tend to attract more abundance under this card, so share what you can and trust that more is on its way.",
  },
  {
    image: "assets/cards/18-moon.jpg",
    name: "The Moon",
    career:
      "When it comes to Career, The Moon warns that things at work may not be what they seem. Information could be incomplete, intentions unclear or rumours misleading. Read between the lines carefully and avoid hasty decisions based on partial facts. This is a time to gather more information before committing to anything major. Trust your instincts if something feels wrong, but also check your fears against reality. Once the uncertainty settles, the right direction will become much clearer.",
    love:
      "In love, The Moon brings deep emotions that may feel confusing or hard to read. You might be unsure of someone's feelings, or uncertain about your own. Fears and insecurities can grow in the dark, so avoid making assumptions or jumping to conclusions. Instead, talk openly about your doubts with kindness and honesty. Dreams and intuition can offer clues, but they need grounding in real conversation. Clarity will come once the fog lifts, so be patient with yourself and your partner.",
    finance:
      "Financially, The Moon advises caution with unclear deals, hidden costs or misleading offers. Something that looks attractive on the surface may come with conditions you have not noticed. Double-check every detail before committing, and ask questions until you fully understand what you are agreeing to. Avoid lending or borrowing money without clear terms. Patience will protect you from costly mistakes, and waiting for the full picture to emerge is far wiser than acting in confusion.",
  },
  {
    image: "assets/cards/19-sun.jpg",
    name: "The Sun",
    career:
      "When it comes to Career, The Sun shines success and recognition on your work. Projects flourish, goals are reached, and your confidence inspires the people around you. This is one of the most positive cards in the deck, signalling achievement, visibility and well-deserved praise. You may receive an award, a promotion or simply the satisfaction of a job done brilliantly. Celebrate the achievements you have earned, share credit generously with your team, and enjoy this bright stage of your career.",
    love:
      "In love, The Sun fills your romantic life with joy, warmth and happiness. Relationships feel light, honest and full of fun, and you may find yourself laughing more with your partner than you have in a long time. If you are single, your positive energy is irresistible, and new connections can begin easily. This card also brings clarity, so any doubts or confusion fade away. Share your happiness openly, celebrate your love, and let yourself enjoy the simple pleasure of being together.",
    finance:
      "Financially, The Sun brings prosperity and stability. Investments and efforts are likely to pay off generously, and you may feel a welcome sense of security and comfort. This is a good time to enjoy the rewards of your hard work, perhaps by treating yourself or the people you love. Keep a sensible plan in place so that good fortune continues. Share your success with others where you can, as generosity under this card tends to bring even more warmth and abundance back to you.",
  },
  {
    image: "assets/cards/20-judgement.jpg",
    name: "Judgement",
    career:
      "When it comes to Career, Judgement signals that a calling or important evaluation is arriving. You may be reviewed, assessed or offered an opportunity that asks you to step up. Take time to reflect honestly on your journey so far, including what you have learned and what you want next. Then answer the call with confidence. This card marks a moment of awakening, when you realise your true purpose and choose a new direction that feels like the start of a more meaningful chapter.",
    love:
      "In love, Judgement asks you to look honestly at your relationship and what it truly needs. This may be a time of reflection, where past hurts are examined and forgiven. Renewal is strongly favoured, so a relationship may be reborn with fresh understanding, or an old connection may return for a meaningful second chance. If you are single, consider what past relationships have taught you. Making peace with the past frees you to choose love more wisely and wholeheartedly in the future.",
    finance:
      "Financially, Judgement encourages you to review past decisions and learn from them. Look clearly at what has worked and what has not, without harsh self-criticism. A thorough assessment now will lead to wiser and more confident choices going forward. Old financial matters, such as outstanding debts, disputes or unfinished paperwork, may finally be resolved. This is a good moment to make a fresh start, setting new goals based on everything you have learned.",
  },
  {
    image: "assets/cards/21-world.jpg",
    name: "The World",
    career:
      "When it comes to Career, The World shows that a major goal has been achieved and an important cycle is complete. You may finish a big project, graduate, reach a milestone or gain recognition for years of effort. Travel, international work or expansion into new areas may follow. Take time to celebrate your success fully before reaching for the next horizon. This card marks a moment of wholeness and accomplishment, and you deserve to enjoy the satisfaction of how far you have come.",
    love:
      "In love, The World brings a sense of wholeness, fulfilment and completion. A relationship may reach a significant milestone such as moving in together, marriage or a deep new level of understanding. You feel at peace with each other and with yourselves. If you are single, you may feel complete on your own, which makes you ready to share your life with someone from a place of strength. Enjoy the deep harmony you have built, because this is love that feels like coming home.",
    finance:
      "Financially, The World shows that goals are being reached and stability feels secure. You may complete a savings target, pay off a significant debt or see long-term efforts finally pay off. Celebrate these accomplishments, but do so wisely so that your foundation stays strong. As one chapter closes, a new one of opportunity begins. Use the confidence you have gained to set bigger goals, knowing you have already proven you can achieve what you set out to do.",
  },
];
