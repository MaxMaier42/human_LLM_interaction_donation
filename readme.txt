- main_data -> main dataset that is used throughout
-main_analysis -> runs the main analyses and stores the output to main_analysis_files
- perception_robustness -> checks whether the results are robust when subsetting 1) only to participants who thought they received advice from a human in human advisor (advisee_believed_human, all participants in the LLM advisor condition thought they received advice from an LLM) and 2) only to participants where both the advisor and the advisee believed they chatted with a human in the human advisor condition (dyads_believed_human)
- gpt_donation_baseline -> querying GPT on how much it would donate if it was a participant in the experiment or needed to advice in a one-shot setting 
- qual_analysis -> different analyses of the chat transcript

Note: Transcripts of conversations have been removed from the repo to ensure participant privacy.