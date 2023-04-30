/*
 * Copyright (C) 2007 by
 *
 * 	Xuan-Hieu Phan
 *	hieuxuan@ecei.tohoku.ac.jp or pxhieu@gmail.com
 * 	Graduate School of Information Sciences
 * 	Tohoku University
 *
 * Copyright (C) 2020 by
 *
 * 	Kohei Watanabe
 * 	watanabe.kohei@gmail.com
 *
 * GibbsLDA++ is a free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * GibbsLDA++ is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with GibbsLDA++; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA.
 */

/*
 * References:
 * + The Java code of Gregor Heinrich (gregor@arbylon.net)
 *   http://www.arbylon.net/projects/LdaGibbsSampler.java
 * + "Parameter estimation for text analysis" by Gregor Heinrich
 *   http://www.arbylon.net/publications/text-est.pdf
 */

#include "lib.h"
#include "dev.h"

using namespace std;
using namespace Rcpp;
using namespace quanteda;

// LDA model
class LDA {
    public:
        // --- model parameters and variables ---
        int M; // dataset size (i.e., number of docs)
        int V; // vocabulary size
        int K; // number of topics
        double alpha, beta; // parameters for smoothing
        int max_iter; // number of Gibbs sampling iterations
        int iter; // the iteration at which the model was saved
        int random; // seed for random number generation
        bool verbose; // print progress messages

        // topic transition
        double gamma; // parameter for topic transition
        std::vector<bool> first; // first[i], documents i are first sentence, size M
        arma::vec q; // temp variable for previous document

        arma::sp_mat data; // transposed document-feature matrix
        arma::vec p; // temp variable for sampling
        Texts z; // topic assignments for words, size M x doc.size()
        arma::umat nw; // nw[i][j]: number of instances of word/term i assigned to topic j, size V x K
        arma::umat nd; // nd[i][j]: number of words in document i assigned to topic j, size M x K
        arma::urowvec nwsum; // nwsum[j]: total number of words assigned to topic j, size K
        arma::ucolvec ndsum; // nasum[i]: total number of words in document i, size M
        arma::mat theta; // theta: document-topic distributions, size M x K
        arma::mat phi; // phi: topic-word distributions, size K x V

        // prediction with fitted model
        arma::umat nw_ft;
        arma::urowvec nwsum_ft;

        // random number generators
        std::default_random_engine generator;
        std::uniform_real_distribution<double> random_prob;
        std::uniform_int_distribution<int> random_topic;

        // --------------------------------------

        // constructor
        LDA(int K, double alpha, double beta, double gamma, int max_iter,
            int random, bool verbose);

        // set default values for variables
        void set_default_values();
        void set_data(arma::sp_mat mt, std::vector<bool> first);
        void set_fitted(arma::sp_mat mt);

        // init for estimation
        int init_est();

        // estimate LDA model using Gibbs sampling
        void estimate();
        int sampling(int m, int n, int w);
        void compute_theta();
        void compute_phi();

};

LDA::LDA(int K, double alpha, double beta, double gamma, int max_iter,
         int random, bool verbose) {

    set_default_values();
    this->K = K;
    if(alpha > 0)
        this->alpha = alpha;
    if (beta > 0)
        this->beta = beta;
    if (gamma > 0)
        this->gamma = gamma;
    if (max_iter > 0)
        this->max_iter = max_iter;
    this->random = random;
    this->verbose = verbose;

}

void LDA::set_default_values() {

    M = 0;
    V = 0;
    K = 100;
    alpha = 0.5;
    beta = 0.1;
    max_iter = 2000;
    iter = 0;
    verbose = false;
    random = 1234;
    gamma = 0;
    first = std::vector<bool>(M);

}

void LDA::set_data(arma::sp_mat mt, std::vector<bool> first) {

    data = mt.t();
    M = data.n_cols;
    V = data.n_rows;
    this->first = first;

    //printf("M = %d, V = %d\n", M, V);
}

void LDA::set_fitted(arma::sp_mat words) {

    if ((int)words.n_rows != V || (int)words.n_cols != K)
        throw std::invalid_argument("Invalid word matrix");
    nw_ft = arma::conv_to<arma::umat>::from(arma::mat(words));
    nwsum_ft = arma::sum(nw_ft, 0);

}

int LDA::init_est() {

    if (verbose) {
        Rprintf("Fitting LDA with %d topics\n", K);
        Rprintf("   ...initializing\n");
    }

    std::default_random_engine generator(random);
    std::uniform_real_distribution< double > random_prob(0, 1);
    std::uniform_int_distribution< int > random_topic(0, K - 1);

    z = Texts(M);

    p = arma::vec(K);
    theta = arma::mat(M, K, arma::fill::zeros);
    phi = arma::mat(K, V, arma::fill::zeros);

    nw = arma::umat(V, K, arma::fill::zeros);
    nd = arma::umat(M, K, arma::fill::zeros);
    nwsum = arma::urowvec(K, arma::fill::zeros);
    ndsum = arma::conv_to<arma::ucolvec>::from(arma::mat(arma::sum(data, 0)));

    q = arma::vec(K);

    //dev::Timer timer;
    //dev::start_timer("Set z", timer);
    for (int m = 0; m < M; m++) {

        z[m] = Text(ndsum[m]);
        if (z[m].size() == 0) continue;
        int n = 0;

        arma::sp_mat::const_col_iterator it = data.begin_col(m);
        arma::sp_mat::const_col_iterator it_end = data.end_col(m);
        for(; it != it_end; ++it) {
            int w = it.row();
            int F = *it;
            for (int f = 0; f < F; f++) {
                int topic = random_topic(generator);
                z[m][n] = topic;
                // number of instances of word i assigned to topic j
                nw.at(w, topic) += 1;
                // number of words in document i assigned to topic j
                nd.at(m, topic) += 1;
                // total number of words assigned to topic j
                nwsum[topic] += 1;
                n++;
            }
        }
    }
    //dev::stop_timer("Set z", timer);

    return 0;
}

void LDA::estimate() {

    if (verbose)
        Rprintf("   ...Gibbs sampling in %d itterations\n", max_iter);

    int last_iter = iter;
    for (iter = last_iter + 1; iter <= max_iter + last_iter; iter++) {

        if (iter % 100 == 0) {
            checkUserInterrupt();
            if (verbose)
                Rprintf("   ...iteration %d\n", iter);
        }

        // for all z_i
        for (int m = 0; m < M; m++) {

            // topic of the previous document
            for (int k = 0; k < K; k++) {
                if (gamma == 0 || first[m] || m == 0) {
                    q[k] = 1.0;
                } else {
                    q[k] = pow((nd.at(m - 1, k) + alpha) / (ndsum[m - 1] + K * alpha), gamma);
                }
            }
            //Rcout << m << ":\n";
            //Rcout << q << "\n";

            if (z[m].size() == 0) continue;
            int n = 0;

            arma::sp_mat::const_col_iterator it = data.begin_col(m);
            arma::sp_mat::const_col_iterator it_end = data.end_col(m);
            for(; it != it_end; ++it) {
                int w = it.row();
                int F = *it;
                //printf("Sampling %d %d %d %d\n", iter, m, w, F);
                for (int f = 0; f < F; f++) {
                    z[m][n] = sampling(m, n, w);
                    n++;
                }
            }
        }
    }

    if (verbose)
        Rprintf("   ...computing theta and phi\n");
    //compute_theta();
    //compute_phi();
    iter--;
    if (verbose)
        Rprintf("   ...complete\n");
}

int LDA::sampling(int m, int n, int w) {

    // remove z_i from the count variables
    int topic = z[m][n];
    nw.at(w, topic) -= 1;
    nd.at(m, topic) -= 1;
    nwsum[topic] -= 1;
    ndsum[m] -= 1;

    double Vbeta = V * beta;
    double Kalpha = K * alpha;
    // do multinomial sampling via cumulative method
    for (int k = 0; k < K; k++) {
        p[k] = (nw.at(w, k) + nw_ft.at(w, k) + beta) / (nwsum[k] + nwsum_ft[k] + Vbeta) *
               ((nd.at(m, k) + alpha) / (ndsum[m] + Kalpha)) * q[k];
    }
    // cumulate multinomial parameters
    for (int k = 1; k < K; k++) {
        p[k] += p[k - 1];
    }
    // scaled sample because of unnormalized p[]
    double u = random_prob(generator) * p[K - 1];

    // rejection sampling
    for (int k = 0; k < K; k++) {
        topic = k;
        if (p[k] > u) {
            break;
        }
    }

    // add newly estimated z_i to count variables
    nw.at(w, topic) += 1;
    nd.at(m, topic) += 1;
    nwsum[topic] += 1;
    ndsum[m] += 1;

    return topic;
}

void LDA::compute_theta() {
    for (int m = 0; m < M; m++) {
        for (int k = 0; k < K; k++) {
            theta.at(m, k) = (nd.at(m, k) + alpha) / (ndsum[m] + K * alpha);
        }
    }
}

void LDA::compute_phi() {
    for (int k = 0; k < K; k++) {
        for (int w = 0; w < V; w++) {
            phi.at(k, w) = (nw.at(w, k) + nw_ft.at(w, k) + beta) / (nwsum[k] + nwsum_ft[k] + V * beta);
        }
    }
}
