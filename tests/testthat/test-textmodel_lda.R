require(quanteda)

options(seededlda_residual_name = "other")

toks <- tokens(data_corpus_moviereviews[1:500],
               remove_punct = TRUE,
               remove_symbols = TRUE,
               remove_number = TRUE)
dfmt <- dfm(toks) %>%
    dfm_remove(stopwords(), min_nchar = 2) %>%
    dfm_trim(max_docfreq = 0.1, docfreq_type = "prop")
sifi <- c("space", "mars", "alien", "earth")

test_that("LDA is working", {

    skip_on_os("mac")
    skip_on_cran()

    set.seed(1234)
    lda <- textmodel_lda(dfmt, k = 5, max_iter = 200)
    # saveRDS(lda, "tests/data/lda.RDS")
    #lda_v081 <- readRDS("../data/lda_v081.RDS")
    #expect_equal(lda$phi, lda_v081$phi)
    #expect_equal(lda$theta, lda_v081$theta)

    expect_equal(dim(terms(lda, 10)), c(10, 5))
    expect_equal(dim(terms(lda, 20)), c(20, 5))
    expect_equal(
        colnames(terms(lda)),
        c("topic1", "topic2", "topic3", "topic4", "topic5")
    )
    expect_true(
        sum(apply(terms(lda), 2, function(x)  all(sifi %in% x))) == 1 # there is the sifi topic
    )
    expect_equal(
        names(topics(lda)),
        docnames(lda$data)
    )
    expect_setequal(
       topics(lda),
       c("topic1", "topic2", "topic3", "topic4", "topic5")
    )
    expect_equal(
        levels(topics(lda)),
        c("topic1", "topic2", "topic3", "topic4", "topic5")
    )
    expect_equal(
        rowSums(lda$phi),
        c("topic1" = 1, "topic2" = 1, "topic3" = 1, "topic4" = 1, "topic5" = 1)
    )
    expect_equal(
        rowSums(lda$theta),
        structure(rep(1, ndoc(dfmt)), names = docnames(dfmt))
    )
    expect_equal(
        ncol(terms(textmodel_lda(dfmt, k = 1))), 1
    )
    expect_equal(
        ncol(terms(textmodel_lda(dfmt, k = 10))), 10
    )
    expect_error(
        textmodel_lda(dfmt, k = 0),
        "The value of k must be between 1 and 1000"
    )

    expect_output(
        print(lda),
        paste0("\nCall:\n",
               "textmodel_lda(x = dfmt, k = 5, max_iter = 200)\n\n",
               "5 topics; 500 documents; 22,544 features."),
        fixed = TRUE
    )
    expect_equal(
        names(lda),
        c("k", "max_iter", "last_iter", "auto_iter", "adjust_alpha",
          "alpha", "beta", "epsilon", "gamma",
          "phi", "theta", "words", "data", "batch_size", "call", "version")
    )
    expect_equal(lda$last_iter, 200)
    expect_equivalent(class(lda$words), "dgCMatrix")
    expect_equal(rownames(lda$words), colnames(lda$phi))
    expect_equal(colnames(lda$words), rownames(lda$phi))
})

test_that("alpha and beta work", {

    lda <- textmodel_lda(dfmt, max_iter = 200)
    expect_equal(lda$alpha, rep(0.5, 10))
    expect_equal(lda$beta, rep(0.1, 10))

    lda2 <- textmodel_lda(dfmt, alpha = 0.7, beta = 0.2, max_iter = 200)
    expect_equal(lda2$alpha, rep(0.7, 10))
    expect_equal(lda2$beta, rep(0.2, 10))

    expect_error(
        textmodel_lda(dfmt, alpha = -0.1),
        "The value of alpha must be between 0 and Inf"
    )

    expect_error(
    	textmodel_lda(dfmt, alpha = rep(0.5, 5)),
    	"The length of alpha must be 10"
    )

    expect_error(
        textmodel_lda(dfmt, beta = -0.1),
        "The value of beta must be between 0 and Inf"
    )

    expect_error(
    	textmodel_lda(dfmt, beta = rep(0.1, 5)),
    	"The length of beta must be 10"
    )

})

test_that("adjust_alpha works", {

	skip_on_os("mac")
	skip_on_cran()

	set.seed(1234)
	lda <- textmodel_lda(dfmt, max_iter = 200, adjust_alpha = 0.5)

	expect_equivalent(rowSums(lda$theta), rep(1.0, ndoc(lda$data)))
	expect_equivalent(rowSums(lda$phi), rep(1.0, lda$k))

	expect_equal(lda$adjust_alpha, 0.5)
	expect_true(all(lda$alpha != 0.5))
	expect_true(all(lda$epsilon > 0))

	expect_error(
		textmodel_lda(dfmt, max_iter = 200, adjust_alpha = 1.5),
		"The value of adjust_alpha must be between 0 and 1"
	)

	expect_error(
		textmodel_lda(dfmt, max_iter = 200, adjust_alpha = -0.5),
		"The value of adjust_alpha must be between 0 and 1"
	)

	expect_error(
		textmodel_lda(dfmt, max_iter = 200, adjust_alpha = c(0.5, 0.5)),
		"The length of adjust_alpha must be 1"
	)
})

test_that("verbose works", {

    expect_output(
        lda1 <- textmodel_lda(dfmt, k = 5, verbose = TRUE, max_iter = 200),
        paste("Fitting LDA with 5 topics\n",
              " [.]{3}initializing\n",
              " [.]{3}Gibbs sampling in 200 iterations\n",
              " [.]{6}iteration 100 elapsed time: .*\n",
              " [.]{6}iteration 200 elapsed time: .*\n",
              " [.]{3}computing theta and phi\n",
              " [.]{3}complete", sep = "")
    )

    expect_output(
        suppressWarnings(
         lda2 <- textmodel_lda(dfmt, k = 5, verbose = TRUE, max_iter = 200, model = lda1)
        ),
        paste("Fitting LDA with 5 topics\n",
            " [.]{3}loading fitted model\n",
            " [.]{3}initializing\n",
            " [.]{3}Gibbs sampling in 200 iterations\n",
            " [.]{6}iteration 100 elapsed time: .*\n",
            " [.]{6}iteration 200 elapsed time: .*\n",
            " [.]{3}computing theta and phi\n",
            " [.]{3}complete", sep = "")
    )

    expect_output(
        lda3 <- textmodel_lda(dfmt, k = 5, verbose = TRUE, max_iter = 100, batch_size = 0.5),
        paste("Fitting LDA with 5 topics\n",
            " [.]{3}initializing\n",
            "( [.]{3}using up to .* threads for distributed computing\n)?",
            "( [.]{6}allocating .* documents to each thread\n)?",
            " [.]{3}Gibbs sampling in 100 iterations\n",
            "( [.]{6}iteration 100 elapsed time: .*\n)?",
            " [.]{3}computing theta and phi\n",
            " [.]{3}complete", sep = "")
    )

    expect_output(
        lda4 <- textmodel_lda(dfmt, k = 5, verbose = TRUE, max_iter = 200,
                              auto_iter = TRUE, batch_size = 0.5),
        paste("Fitting LDA with 5 topics\n",
              " [.]{3}initializing\n",
              "( [.]{3}using up to .* threads for distributed computing\n)?",
              "( [.]{6}allocating .* documents to each thread\n)?",
              " [.]{3}Gibbs sampling in up to 200 iterations\n",
               sep = "")
    )
})

test_that("LDA works with empty documents", {

    dfmt_empty <- dfmt
    dfmt_empty[c(100, 200, 300),] <- 0
    dfmt_empty <- as.dfm(dfmt_empty)

    set.seed(1234)
    lda_empty <- textmodel_lda(dfmt_empty, k = 5)
    expect_true(
        all(is.na(topics(lda_empty)[c(100, 200, 300)]))
    )

})

test_that("model argument works with LDA", {
    skip_on_cran()

    dfmt_train <- dfm_trim(head(dfmt, 450))
    dfmt_test <- dfm_trim(tail(dfmt, 50))

    # fit new model
    lda <- textmodel_lda(dfmt_train, k = 5)

    # in-sample prediction
    expect_warning({
        lda1 <- textmodel_lda(dfmt_train[1:50,], model = lda)
    }, "k, alpha, beta and gamma values are overwritten by the fitted model")
    expect_false(all(lda$phi == lda1$phi))
    expect_identical(dimnames(lda$phi), dimnames(lda1$phi))
    expect_true(mean(topics(lda)[1:50] == topics(lda1)) > 0.8)
    expect_equal(
        levels(topics(lda1)),
        c("topic1", "topic2", "topic3", "topic4", "topic5")
    )

    # out-of-sample prediction
    expect_warning({
        lda2 <- textmodel_lda(dfmt_test, model = lda)
    }, "k, alpha, beta and gamma values are overwritten by the fitted model")
    expect_identical(dimnames(lda$phi), dimnames(lda2$phi))
    expect_equal(
        levels(topics(lda2)),
        c("topic1", "topic2", "topic3", "topic4", "topic5")
    )

    # out-of-sample with new words
    expect_warning({
    	lda3 <- textmodel_lda(dfmt_test, model = lda, update_model = TRUE)
    }, "k, alpha, beta and gamma values are overwritten by the fitted model")
    expect_false(identical(dimnames(lda$phi), dimnames(lda3$phi)))
    expect_equal(
    	levels(topics(lda3)),
    	c("topic1", "topic2", "topic3", "topic4", "topic5")
    )
})

test_that("select and min_prob are working", {

    set.seed(1234)
    lda <- textmodel_lda(dfmt, k = 5)

    expect_equal(
        is.na(topics(lda, min_prob = 0.50)),
        rowSums(lda$theta > 0.50) == 0
    )
    expect_equal(
        is.na(topics(lda, min_prob = 0.25)),
        rowSums(lda$theta > 0.25) == 0
    )

    expect_equal(
        is.na(topics(lda, min_prob = 0.1, select = c("topic1", "topic2", "topic5"))),
        rowSums(lda$theta[, c(1, 2, 5)] > 0.1) == 0
    )

    expect_error(
        topics(lda, min_prob = -0.1),
        "The value of min_prob must be between 0 and 1"
    )

    expect_error(
        topics(lda, min_prob = c(0.1, 0.2)),
        "The length of min_prob must be 1"
    )

    expect_equal(
        topics(lda)[10:20],
        topics(lda, select = paste0("topic", 1:5))[10:20]
    )

    expect_equal(
        as.integer(topics(lda, select = c("topic1", "topic2", "topic5")))[1:10],
        max.col(lda$theta[,c(1, 2, 5)])[1:10]
    )

    # keep the order of levels
    expect_identical(
        levels(topics(lda, select = c("topic3", "topic2"))[1:10]),
        levels(topics(lda, select = c("topic2", "topic3"))[1:10])
    )

    # invalid input
    expect_error(
        topics(lda, select = 1:2),
        "The type of select must be character"
    )

    expect_error(
        topics(lda, select = c(TRUE, FALSE)),
        "The type of select must be character"
    )

    expect_error(
        topics(lda, select = character()),
        "The length of select must be between 1 and 5"
    )

    expect_error(
        topics(lda, select = c("topic2", "xxxxx")),
        "Selected topics must be in the model"
    )

})

test_that("distributed LDA works", {

    # batch sizes
    expect_error(
        textmodel_lda(dfmt, k = 5, batch_size = 0, max_iter = 200, verbose = FALSE),
        "batch_size musht be larger than 0"
    )
    expect_error(
        textmodel_lda(dfmt, k = 5, batch_size = -1.0, max_iter = 200, verbose = FALSE),
        "The value of batch_size must be between 0 and 1", fixed = TRUE
    )
    expect_error(
        textmodel_lda(dfmt, k = 5, batch_size = 2.0, max_iter = 200, verbose = FALSE),
        "The value of batch_size must be between 0 and 1", fixed = TRUE
    )

    # threads
    options(seededlda_threads = "a")
    expect_error(
        textmodel_lda(dfmt, k = 5, batch_size = 0.2, max_iter = 200, verbose = FALSE),
        'seededlda_threads must be an integer', fixed = TRUE
    )
    options(seededlda_threads = -1) # use all threads
    expect_silent(
        lda1 <- textmodel_lda(dfmt, k = 5, batch_size = 0.2, max_iter = 200, verbose = FALSE)
    )
    expect_equal(lda1$batch_size, 0.2)

    options(seededlda_threads = 2)
    expect_output(
        lda2 <- textmodel_lda(dfmt, k = 5,  batch_size = 0.2, max_iter = 200, verbose = TRUE),
        ".*using up to 2 threads for distributed computing.*"
    )
    expect_equal(lda2$batch_size, 0.2)

    # reset
    options(seededlda_threads = NULL)
})

test_that("auto_iter works", {
    expect_error(
        textmodel_lda(dfmt, k = 5, auto_iter = -1, verbose = FALSE),
        "The type of auto_iter must be logical"
    )
    expect_silent(
        textmodel_lda(dfmt, k = 5, auto_iter = TRUE, verbose = FALSE)
    )
})

