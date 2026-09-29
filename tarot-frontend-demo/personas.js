// The 22 Major Arcana. `image` is the card face: it is decoded and bound to
// the Rive view model's `face` image, and shown on the final screen.
// Card art: Rider–Waite–Smith (1909), public domain, via Wikimedia Commons.
const TAROT_PERSONAS = [
  {
    image: "assets/cards/00-fool.jpg",
    name: "The Fool",
    description:
      "Standing at the edge of a cliff with his eyes on the sky, the Fool is the spirit of new beginnings. He invites you to step forward with an open heart, trusting the journey before you can see where it leads. Spontaneity, curiosity and faith in the unknown are your companions now; let go of what holds you back and allow yourself to begin again.",
  },
  {
    image: "assets/cards/01-magician.jpg",
    name: "The Magician",
    description:
      "With one hand raised to the heavens and one pointing to the earth, the Magician channels intention into action. Every tool you need is already on the table before you. This is a time of skill, focus and willpower, when ideas can be made real through concentration and confidence. Trust your abilities and act with clear purpose.",
  },
  {
    image: "assets/cards/02-high-priestess.jpg",
    name: "The High Priestess",
    description:
      "Seated between the pillars of light and shadow, the High Priestess guards the knowledge that lies beneath the surface. She asks you to be still and listen to your intuition, dreams and quiet inner voice. Not every answer arrives through reason; some are felt before they are understood. Trust what you sense, and let hidden truths reveal themselves in time.",
  },
  {
    image: "assets/cards/03-empress.jpg",
    name: "The Empress",
    description:
      "Surrounded by ripening wheat and flowing water, the Empress embodies abundance, nurture and creation. She reminds you to care for yourself and others with warmth, and to take pleasure in beauty, comfort and the natural world. Ideas and relationships tended with patience will flourish. Allow growth to happen at its own gentle pace.",
  },
  {
    image: "assets/cards/04-emperor.jpg",
    name: "The Emperor",
    description:
      "Upon his stone throne, the Emperor represents structure, authority and steady leadership. He encourages you to bring order to your plans, set clear boundaries and take responsibility for your path. Discipline and reliability create the foundation on which lasting success is built. Lead with fairness, and let your strength protect what you value.",
  },
  {
    image: "assets/cards/05-hierophant.jpg",
    name: "The Hierophant",
    description:
      "Symbolizing tradition, faith and learning, he protects the inheritance of wisdom and ethics. The Pope reminds people to follow rules and social values while growing through guidance, education and experience. He emphasizes seeking wisdom and support in the process of exploring spirituality or knowledge. He also encourages learning from other people's experiences and understanding the balance between inner beliefs and outer practices.",
  },
  {
    image: "assets/cards/06-lovers.jpg",
    name: "The Lovers",
    description:
      "Blessed by an angel above them, the Lovers speak of connection, harmony and meaningful choice. This card reflects relationships built on honesty and shared values, and decisions made from the heart. It asks you to align your actions with what you truly believe. When you choose with integrity, love and trust grow stronger.",
  },
  {
    image: "assets/cards/07-chariot.jpg",
    name: "The Chariot",
    description:
      "The charioteer holds two opposing sphinxes in line through willpower alone. This card celebrates determination, self-control and victory earned through focus. Challenges may pull you in different directions, but steady resolve keeps you moving forward. Set your course, hold the reins firmly, and success is within reach.",
  },
  {
    image: "assets/cards/08-strength.jpg",
    name: "Strength",
    description:
      "A woman gently closes the jaws of a lion, showing that true strength is quiet and kind. This card speaks of courage, patience and compassion, especially toward yourself. Difficult emotions and situations are best met with calm confidence rather than force. Your inner resilience is greater than you know.",
  },
  {
    image: "assets/cards/09-hermit.jpg",
    name: "The Hermit",
    description:
      "Holding a lantern on a snowy peak, the Hermit seeks the light of inner wisdom. He invites you to step back from the noise of the world and reflect. Solitude now is not loneliness but a chance to understand yourself more deeply. The guidance you are looking for may be found within.",
  },
  {
    image: "assets/cards/10-wheel-of-fortune.jpg",
    name: "Wheel of Fortune",
    description:
      "The great wheel turns, carrying all things through cycles of rise and fall. This card signals change, destiny and turning points. Luck may shift in your favor, and events beyond your control can open new doors. Embrace the movement of life, knowing that every phase passes and a new chapter is always beginning.",
  },
  {
    image: "assets/cards/11-justice.jpg",
    name: "Justice",
    description:
      "With a sword in one hand and scales in the other, Justice stands for truth, fairness and accountability. She reminds you that actions carry consequences and that clarity comes from honesty. Weigh decisions carefully and act with integrity. Balance will be restored when what is right is honored.",
  },
  {
    image: "assets/cards/12-hanged-man.jpg",
    name: "The Hanged Man",
    description:
      "Suspended upside down yet serene, the Hanged Man sees the world from a new angle. This card asks you to pause, surrender and let go of the need to force outcomes. A period of waiting can bring unexpected insight. By releasing old perspectives, you make room for a new understanding.",
  },
  {
    image: "assets/cards/13-death.jpg",
    name: "Death",
    description:
      "Rarely about an ending in the literal sense, Death marks transformation and renewal. Something in your life is completing its cycle so that something new can begin. Release what no longer serves you with grace. Change may feel uncertain, but it clears the path for growth and rebirth.",
  },
  {
    image: "assets/cards/14-temperance.jpg",
    name: "Temperance",
    description:
      "An angel pours water between two cups, blending opposites into harmony. Temperance speaks of balance, moderation and patience. It encourages you to find the middle path and combine different parts of your life with care. Healing and steady progress come from calm, measured steps.",
  },
  {
    image: "assets/cards/15-devil.jpg",
    name: "The Devil",
    description:
      "The chained figures beneath the Devil could free themselves at any time. This card shines a light on habits, attachments and fears that quietly hold you back. Awareness is the first step to freedom. Look honestly at what binds you, and remember that you have the power to choose differently.",
  },
  {
    image: "assets/cards/16-tower.jpg",
    name: "The Tower",
    description:
      "Struck by lightning, the Tower represents sudden change and the collapse of false foundations. Though unsettling, this upheaval clears away what was never stable. Truths come to light and illusions fall. From the rubble, you can rebuild on firmer ground with greater clarity.",
  },
  {
    image: "assets/cards/17-star.jpg",
    name: "The Star",
    description:
      "Beneath a sky full of light, the Star pours water onto land and sea, offering hope and renewal. After difficulty comes healing and a sense of peace. This card encourages you to have faith in the future and to trust your dreams. Stay open, and let inspiration guide you forward.",
  },
  {
    image: "assets/cards/18-moon.jpg",
    name: "The Moon",
    description:
      "The Moon lights a winding path between two towers, where not everything is as it seems. This card speaks of intuition, dreams and the unknown. Feelings may be heightened and situations unclear. Move carefully, trust your instincts, and allow the truth to emerge as the night gives way to dawn.",
  },
  {
    image: "assets/cards/19-sun.jpg",
    name: "The Sun",
    description:
      "A joyful child rides beneath a radiant sun, embodying warmth, success and vitality. This is one of the most positive cards in the deck, bringing clarity, confidence and happiness. Share your light freely and celebrate what is going well. Brighter days are here.",
  },
  {
    image: "assets/cards/20-judgement.jpg",
    name: "Judgement",
    description:
      "At the angel's call, figures rise to answer a higher purpose. Judgement represents awakening, reflection and a fresh start. It invites you to review the past honestly, forgive yourself and others, and listen to your true calling. A meaningful new chapter is ready to begin.",
  },
  {
    image: "assets/cards/21-world.jpg",
    name: "The World",
    description:
      "Encircled by a victory wreath, the dancer of the World marks completion and fulfillment. A journey has reached its natural end, and you can take pride in how far you have come. This card celebrates wholeness, achievement and harmony. Enjoy the moment before the next adventure begins.",
  },
];
