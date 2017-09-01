#!/usr/bin/env python3

import os

#data file
trinity_fasta="data/Trinity.fasta"

#results files
transdecoder_results="output/transdecoder/Trinity.fasta.transdecoder.pep"
blast_db="bin/trinotate/db/uniprot_sprot.pep"
blastp_results="output/blastp/blastp.outfmt6"
blastx_results="output/blastx/blastx.outfmt6"
hmmer_db="bin/trinotate/trinotate/Pfam-A.hmm"
hmmer_results="output/hmmer/TrinotatePFAM.out"
rnammer_results="output/rnammer/Trinity.fasta.rnammer.gff"
tmhmm_results="output/tmhmm/tmhmm.out"
renamed_transdecoder="output/signalp/renamed_transdecoder_results.fasta"
ids="output/signalp/ids.csv"
signalp_results="output/signalp/signalp.out"
signalp_gff="output/signalp/signalp.gff"
signalp_renamed_gff="output/signalp/renamed_signalp_gff.gff2"
trinotate_database="output/trinotate/Trinotate.sqlite"
trinity_gene_trans_map="output/trinotate/Trinity.fasta.gene_trans_map"
trinotate_annotation_report="output/trinotate/trinotate_annotation_report.txt"
sqlite_db="bin/trinotate/db/Trinotate.sqlite"

#intermediate files
log_directory="output/logs"
transdecoder_directory=os.path.split(transdecoder_results)[0]
rnammer_directory=os.path.split(rnammer_results)[0]

#rules
rule all:
	input:
		trinotate_annotation_report

rule run_transdecoder:
	input:
		trinity_fasta=trinity_fasta
	output:
		transdecoder_results,
		td_fasta=temp(os.path.join(transdecoder_directory,'Trinity.fasta')),
		w_dir=transdecoder_directory
	threads:
		1
	shell:
		'cp {input.trinity_fasta} {output.td_fasta} ; '
		'cd {output.w_dir} ; '
		'TransDecoder.LongOrfs -t Trinity.fasta -S ; '
		'TransDecoder.Predict -t Trinity.fasta'

rule run_blastp:
	input:
		transdecoder_results=transdecoder_results,
		db=blast_db
	output:
		blastp_results
	threads:
		50
	log:
		os.path.join(log_directory, 'blastp.log')
	shell:
		'blastp '
		'-db {input.db} '
		'-query {input.transdecoder_results} '
		'-num_threads {threads} '
		'-max_target_seqs 1 '
		'-outfmt 6 > {output} '
		'2> {log}'

rule run_blastx:
	input:
		trinity_fasta=trinity_fasta,
		db=blast_db
	output:
		blastx_results
	threads:
		50
	log:
		os.path.join(log_directory, 'blastx.log')
	shell:
		'blastx '
		'-db {input.db} '
		'-query {input.trinity_fasta} '
		'-num_threads {threads} '
		'-max_target_seqs 1 '
		'-outfmt 6 > {output} '
		'2> {log}'

rule run_hmmer:
	input:
		transdecoder_results=transdecoder_results
		db=hmmer_db
	output:
		hmmer_results
	threads:
		50
	log:
		os.path.join(log_directory, 'hmmer.log')
	shell:
		'hmmscan '
		'--cpu {threads} '
		'--domtblout {output} '
		'{input.db} '
		'{input.transdecoder_results} '
		'> {log}'

rule run_rnammer:
	input:
		trinity_fasta
	output:
		rnammer_results,
		rn_fasta=temp(os.path.join(rnammer_directory,'Trinity.fasta')),
		w_dir=rnammer_directory
	threads:
		1
	shell:
		'cp {input.trinity_fasta} {output.td_fasta} ; '
		'cd {output.w_dir} ; '
		'RnmmerTranscriptome.pl '
		'--transcriptome {output.rn_fasta} '
		'--path_to_rnammer "$(which rnammer)'

rule run_tmhmm:
	input:
		transdecoder_results
	output:
		tmhmm_results
	log:
		os.path.join(log_directory, 'tmhmm.log')
	threads:
		1
	shell:
		'tmhmm_path="$(readlink -f "$(which tmhmm)")"  ; '
		'"${tmhmm_path}" '
		'-short '
		'< {input} '
		'> {output} '
		'2> {log}'

rule run_rename_transdecoder:
	input:
		transdecoder_results=transdecoder_results
	output:
		renamed_transdecoder=renamed_transdecoder,
		ids=ids
	script:
		src/rename_fasta_headers.py

rule run_signalp:
	input:
		renamed_transdecoder
	output:
		results=signalp_results,
		gff=signalp_gff
	threads:
		1
	shell:
		'signalp '
		'-f short '
		'-n {output.gff} '
		'{input} '
		'> {output.results}'

rule run_rename_signalp_gff:
	input:
		signalp_gff=signalp_gff,
		ids=ids
	output:
		signalp_renamed_gff=signalp_renamed_gff
	script:
		src/rename_gff.R

rule run_gene_to_trans_map:
	input:
		trinity_fasta
	output:
		trinity_gene_trans_map
	shell:
		'get_Trinity_gene_to_trans_map.pl '
		'{input} '
		'> {output}'

rule run_load_trinotate_results:
	input:
		fasta=trinity_fasta,
		gene_trans_map=trinity_gene_trans_map,
		transdecoder=transdecoder_results,
		blastx=blastx_results,
		blastp=blastp_results,
		hmmer=hmmer_results,
		signalp=signalp_renamed_gff,
		tmhmm=tmhmm_results,
		rnammer=rnammer_results
		db=sqlite_db
	output:
		trinotate_database
	shell:
		'cp {input.db} {output} ; '
		'Trinotate '
		'{output} init '
		'--gene_trans_map {input.gene_trans_map} '
		'--transcript_fasta {input.fasta} '
		'transdecoder_pep {input.transdecoder} ; '
		'Trinotate {output} LOAD_swissprot_blastx {input.blastx} ; '
		'Trinotate {output} LOAD_swissprot_blastp {input.blastp} ; '
		'Trinotate {output} LOAD_pfam {input.hmmer} ; '
		'Trinotate {output} LOAD_signalp {input.signalp} ; '
		'Trinotate {output} LOAD_tmhmm {input.tmhmm} ; '
		'Trinotate {output} LOAD_rnammer {input.rnammer} ; '

rule run_trinotate_report:
	input:
		trinotate_database
	output:
		trinotate_annotation_report
	shell:
		'Trinotate {input} report > {output}'









