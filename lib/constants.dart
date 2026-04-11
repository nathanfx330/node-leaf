// --- File: lib/constants.dart ---
import 'package:flutter/material.dart';

const double kWorldSize = 50000.0;
const double kNodeWidth = 320.0; 
const double kNodeHeight = 140.0; // Scratchpad box
const double kPillHeight = 80.0;  // True Toxik-style horizontal pill

const Color kCanvasBg = Color(0xFF0A0A0A); 
const Color kNodeBg = Color(0xFF383838);
const Color kAccentColor = Color(0xFFA22323); 

const Color kSelectGlowColor = Color(0xFFFFD700); 

// Added 'persona', 'summarize', 'wikiReader', 'wikiWriter', 'council', and 'researchParty' to the NodeType enum
enum NodeType { scene, output, search, document, relationship, catalog, intersection, chat, briefing, study, persona, summarize, wikiReader, wikiWriter, council, researchParty } 
enum AuthStatus { none, testing, success, error, mismatch }